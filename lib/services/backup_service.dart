import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/backup_config.dart';
import '../models/backup_cursor_model.dart';
import '../models/backup_snapshot_model.dart';
import '../local_db/app_database.dart';
import '../local_db/daos/message_dao.dart';
import '../local_db/daos/todo_dao.dart';
import '../local_db/daos/comment_dao.dart';
import '../local_db/daos/sticky_note_dao.dart';
import 'auth_service.dart';
import 'backup_cursor_store.dart';
import 'backup_merge.dart';
import 'crypto_service.dart';
import 'firestore_service.dart';
import 'google_drive_service.dart';
import 'local_folder_service.dart';
import 'local_storage_service.dart';
import 'log_service.dart';

/// Outcome of one [BackupService.runBackup] call, detailed enough to show
/// directly in a diagnostics UI without needing to cross-reference logs.
class BackupRunResult {
  final bool success;
  final String message;
  final int todos;
  final int comments;
  final int messages;
  final int stickyNotes;
  // Independent of [success] — the local SAF-folder write is a best-effort
  // side write attempted regardless of how the Drive half of the run goes,
  // so a Drive failure (network, quota) doesn't cost the user a local copy
  // they'd otherwise have gotten. False just means no local folder is
  // connected yet, or that write itself failed — never blocks Drive.
  final bool localBackupWritten;

  const BackupRunResult({
    required this.success,
    required this.message,
    this.todos = 0,
    this.comments = 0,
    this.messages = 0,
    this.stickyNotes = 0,
    this.localBackupWritten = false,
  });
}

/// A read-only snapshot of backup state for manual verification: what the
/// local cursor thinks has been synced, which generations exist on Drive,
/// and how the backup's record counts compare to what's currently live in
/// Firestore.
class BackupInspection {
  final BackupCursor cursor;
  final bool latestExists;
  final List<int> occupiedGenerations;
  final int liveTodoCount;
  final int liveMessageCount;
  final int liveStickyNoteCount;
  final int? backupTodoCount;
  final int? backupMessageCount;
  final int? backupStickyNoteCount;
  final String? error;

  const BackupInspection({
    required this.cursor,
    required this.latestExists,
    required this.occupiedGenerations,
    required this.liveTodoCount,
    required this.liveMessageCount,
    required this.liveStickyNoteCount,
    this.backupTodoCount,
    this.backupMessageCount,
    this.backupStickyNoteCount,
    this.error,
  });
}

/// Orchestrates the full-state backup pipeline: fetch deltas since the
/// local cursor, merge them into a copy of the existing Drive backup,
/// verify it, then atomically promote it — never mutating the last
/// known-good backup until the new one is confirmed good.
class BackupService {
  final FirestoreService _firestore = FirestoreService();
  final GoogleDriveService _drive = GoogleDriveService();
  final AuthService _auth = AuthService();
  final BackupCursorStore _cursorStore = BackupCursorStore();
  final MessageDao _messageDao = MessageDao(AppDatabase.instance());
  final TodoDao _todoDao = TodoDao(AppDatabase.instance());
  final CommentDao _commentDao = CommentDao(AppDatabase.instance());
  final StickyNoteDao _stickyNoteDao = StickyNoteDao(AppDatabase.instance());
  final LocalFolderService _localFolder = LocalFolderService();

  /// Converts row-by-row rather than a single .map().toList() — one
  /// document that fails sanitization (or produces a shape the cast
  /// doesn't expect) must not abort backup of every other document in the
  /// same collection.
  List<Map<String, dynamic>> _sanitizeList(List<Map<String, dynamic>> docs) {
    final result = <Map<String, dynamic>>[];
    for (final doc in docs) {
      try {
        result.add(sanitizeForJson(doc) as Map<String, dynamic>);
      } catch (e) {
        LogService.log('Backup: failed to sanitize doc ${doc['id']}: $e');
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> _currentAllowlistedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, dynamic>{};
    for (final key in BackupConfig.backedUpPreferenceKeys) {
      if (prefs.containsKey(key)) result[key] = prefs.get(key);
    }
    return result;
  }

  /// Applies backed-up preference values to local SharedPreferences. Only
  /// ever writes keys from [BackupConfig.backedUpPreferenceKeys] — the
  /// backup itself only ever contains that allowlist, but this stays
  /// explicit as a second guard against ever writing back internal
  /// bookkeeping keys.
  Future<void> _applyPreferencesLocally(Map<String, dynamic> preferences) async {
    if (preferences.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    for (final key in BackupConfig.backedUpPreferenceKeys) {
      final value = preferences[key];
      if (value == null) continue;
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is List) {
        await prefs.setStringList(key, value.cast<String>());
      }
    }
    LogService.log('Backup: restored ${preferences.length} preference(s) locally');
  }

  /// Fixes the "Never backed up yet" display on a fresh install where a
  /// backup already exists on Drive from a previous install. This is
  /// display-only — it does NOT merge/restore any data, just checks Drive's
  /// file metadata for the last-modified time/size and writes that into the
  /// local cursor. Deliberately independent of [runBackup]'s partner-key
  /// requirement: on a fresh install right after PIN restore, the partner's
  /// public key may not have synced from Firestore yet, so runBackup() can
  /// bail out early without ever touching the cursor — that shouldn't also
  /// mean the UI lies about there being no backup at all. No-ops (and does
  /// no Drive call) once the cursor already has a value, so this is cheap
  /// to call on every app open.
  Future<void> reconcileCursorWithDriveIfNeeded() async {
    final cursor = await _cursorStore.load();
    if (cursor.lastBackupAt != null) return;

    try {
      final metadata = await _drive.getFileMetadata(BackupConfig.latestBackupFileName);
      if (metadata == null) return;
      await _cursorStore.save(cursor.copyWith(
        lastBackupAt: metadata.modifiedTime,
        lastBackupSizeBytes: metadata.sizeBytes,
      ));
      LogService.log(
          'Backup: reconciled cursor with existing Drive backup from ${metadata.modifiedTime}');
    } catch (e) {
      LogService.log('Backup: cursor reconciliation failed: $e');
    }
  }

  // Static, not instance-level: BackupService() is constructed fresh at
  // every call site (main_shell.dart's cold-start await, its
  // AppLifecycleState.resumed fire-and-forget, ForegroundBackupScheduler,
  // and the manual "Run Backup Now" button), so an instance field would
  // never actually catch two of those overlapping. Without this, a resume
  // firing while the cold-start run is still in flight raced on the same
  // cursor read/write and the same Drive generation-rotation filenames,
  // silently losing whichever run's progress wrote last.
  static Future<BackupRunResult>? _inFlightRun;

  /// Runs one incremental backup cycle. Safe to retry — nothing is
  /// advanced/promoted unless the run fully succeeds. If a run is already
  /// in progress (e.g. cold-start backup still running when the app is
  /// quickly backgrounded and resumed), returns that same in-flight run's
  /// result instead of starting a second overlapping one.
  Future<BackupRunResult> runBackup() {
    final existing = _inFlightRun;
    if (existing != null) {
      LogService.log('Backup: run already in progress, joining it instead of starting another');
      return existing;
    }
    final run = _runBackupLocked();
    _inFlightRun = run;
    run.whenComplete(() => _inFlightRun = null);
    return run;
  }

  Future<BackupRunResult> _runBackupLocked() async {
    // Tracked outside the try so a later step throwing (e.g. Drive upload
    // failing after the local write already succeeded) doesn't lose the
    // fact that a durable local copy exists — see the catch block below.
    bool localBackupWrittenBeforeFailure = false;
    try {
      final cursor = await _cursorStore.load();

      final partnerPubKey = await CryptoService().fetchPartnerPublicKey();
      if (partnerPubKey == null) {
        const msg = 'Partner public key unavailable, skipping run';
        LogService.log('Backup: $msg');
        return const BackupRunResult(success: false, message: msg);
      }
      final sharedKey = await CryptoService().getSharedKey(partnerPubKey);

      // 1. Fetch deltas since the cursor (or everything, on the very first
      // run when the cursor fields are all null). Reads from the local DB
      // (kept current by LocalSyncService) instead of Firestore directly —
      // same delta shape either way, see converters.dart's *MapFromRow()
      // functions. _verifyIntegrity() below deliberately still compares
      // against LIVE Firestore, not this local copy, so a broken sync
      // can't silently pass its own integrity check.
      final newTodos = _sanitizeList(await _todoDao.fetchSince(cursor.todosSyncedAt));
      final newComments = _sanitizeList(await _commentDao.fetchSince(cursor.commentsSyncedAt));
      final newMessages = _sanitizeList(await _messageDao.fetchSince(cursor.messagesSyncedAt));
      final newStickyNotes =
          _sanitizeList(await _stickyNoteDao.fetchSince(cursor.stickyNotesSyncedAt));

      final myUid = _auth.currentUser?.uid;
      final partnerUid = await _auth.getPartnerUid();
      final myProfile = myUid != null ? await _firestore.fetchUserDoc(myUid) : null;
      final partnerProfile =
          partnerUid != null ? await _firestore.fetchUserDoc(partnerUid) : null;
      final coupleDocRaw = await _firestore.fetchCoupleDoc(coupleId);

      final deletions = await _firestore.deletionsSince(
        coupleId,
        cursor.deletionsSyncedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

      // 2. Download + decrypt the current backup (or start empty on the
      // very first run, when nothing exists on Drive yet).
      final existing = await _downloadAndDecrypt(sharedKey) ?? BackupSnapshot.empty();

      // 3. Merge deltas and apply tombstones.
      final deletedCommentIds = deletions
          .where((d) => d.collection.endsWith('/comments'))
          .map((d) => d.docId)
          .toSet();

      final mergedTodos = applyTombstones(
          mergeDelta(existing.todos, newTodos), deletions, 'todos');
      final mergedComments = mergeDelta(existing.comments, newComments)
          .where((c) => !deletedCommentIds.contains(c['id']))
          .toList();
      final mergedStickyNotes = applyTombstones(
          mergeDelta(existing.stickyNotes, newStickyNotes), deletions, 'sticky_notes');
      // Messages have no delete feature today, so no tombstone filter needed.
      final mergedMessages = mergeDelta(existing.messages, newMessages);

      final profiles = Map<String, dynamic>.from(existing.profiles);
      if (myUid != null && myProfile != null) {
        profiles[myUid] = sanitizeForJson(myProfile);
      }
      if (partnerUid != null && partnerProfile != null) {
        profiles[partnerUid] = sanitizeForJson(partnerProfile);
      }

      final merged = existing.copyWith(
        generatedAt: DateTime.now(),
        todos: mergedTodos,
        comments: mergedComments,
        messages: mergedMessages,
        stickyNotes: mergedStickyNotes,
        profiles: profiles,
        coupleDoc: coupleDocRaw != null
            ? sanitizeForJson(coupleDocRaw) as Map<String, dynamic>
            : existing.coupleDoc,
        preferences: await _currentAllowlistedPreferences(),
      );

      // 4a. Encrypt once — reused for both the Drive pending file and the
      // local folder write below, rather than encrypting the same snapshot
      // twice.
      final encryptedBytes = await _encrypt(merged, sharedKey);

      // 4b. Upload as the pending file — the last known-good backup on
      // Drive is untouched until this is verified below.
      await _drive.uploadOrReplaceBytes(BackupConfig.pendingBackupFileName, encryptedBytes);
      final backupSizeBytes = encryptedBytes.length;

      // 5. Integrity check: the backup must never contain fewer live
      // records than Firestore currently has (it's fine for it to have
      // more, once purging of old messages is introduced later). Gates
      // BOTH the Drive promotion below and the local-folder write — a
      // snapshot that fails this check must never become the on-device
      // "latest" copy either, since restoreFromBackup() picks whichever of
      // Drive/local has the newest generatedAt and would otherwise prefer
      // a known-bad local copy over a good Drive one.
      final integrity = await _verifyIntegrity(merged);
      if (!integrity.ok) {
        const msg = 'Integrity check failed, aborting promotion';
        LogService.log('Backup: $msg (${integrity.detail})');
        return BackupRunResult(
          success: false,
          message: msg,
          todos: mergedTodos.length,
          comments: mergedComments.length,
          messages: mergedMessages.length,
          stickyNotes: mergedStickyNotes.length,
        );
      }

      // 5a. Local-first write, now that the snapshot has passed integrity —
      // best-effort, independent of Drive's own outcome below.
      final localBackupWritten = await _writeLocalBackup(encryptedBytes);
      localBackupWrittenBeforeFailure = localBackupWritten;

      // 6. Rotate existing generations to make room, then promote.
      await _rotateGenerations();
      await _drive.renameFileByName(
          BackupConfig.pendingBackupFileName, BackupConfig.latestBackupFileName);

      // 7. Advance the cursor to the newest timestamp actually observed in
      // this run's fetched delta — not the device clock, to avoid any
      // device/server clock-skew gap causing a doc to be missed next run.
      final newCursor = cursor.copyWith(
        todosSyncedAt: maxTimestampField(newTodos, 'updatedAt') ?? cursor.todosSyncedAt,
        commentsSyncedAt:
            maxTimestampField(newComments, 'createdAt') ?? cursor.commentsSyncedAt,
        messagesSyncedAt:
            maxTimestampField(newMessages, 'updatedAt') ?? cursor.messagesSyncedAt,
        stickyNotesSyncedAt:
            maxTimestampField(newStickyNotes, 'updatedAt') ?? cursor.stickyNotesSyncedAt,
        deletionsSyncedAt:
            deletions.isNotEmpty ? deletions.last.deletedAt : cursor.deletionsSyncedAt,
        lastBackupAt: DateTime.now(),
        lastBackupSizeBytes: backupSizeBytes,
      );
      await _cursorStore.save(newCursor);

      // 8. Prune tombstones this run has now safely captured.
      if (newCursor.deletionsSyncedAt != null) {
        await _firestore.pruneDeletionsBefore(coupleId, newCursor.deletionsSyncedAt!);
      }

      // 9. Sync locally-saved Snaps to/from Drive — independent of the JSON
      // snapshot above (Snaps live as raw files in their own Drive folder,
      // not inside the encrypted backup blob), so a failure here is logged
      // but never fails the run that already succeeded above.
      try {
        await _syncSnaps();
      } catch (e) {
        LogService.log('Backup: snap sync failed (backup itself still succeeded): $e');
      }

      final msg =
          'Backup completed — ${mergedTodos.length} todos, ${mergedComments.length} comments, ${mergedMessages.length} messages, ${mergedStickyNotes.length} sticky notes';
      LogService.log('Backup: $msg');
      return BackupRunResult(
        success: true,
        message: msg,
        todos: mergedTodos.length,
        comments: mergedComments.length,
        messages: mergedMessages.length,
        stickyNotes: mergedStickyNotes.length,
        localBackupWritten: localBackupWritten,
      );
    } catch (e) {
      final msg = 'Run failed: $e';
      LogService.log('Backup Error: $msg');
      return BackupRunResult(
        success: false,
        message: msg,
        localBackupWritten: localBackupWrittenBeforeFailure,
      );
    }
  }

  /// Downloads and decrypts the latest Drive backup, merges it with
  /// whatever's currently live in Firestore (live wins conflicts).
  ///
  /// By default also resets the local cursor so the next scheduled backup
  /// continues incrementally from here rather than re-diffing everything —
  /// this is the real reinstall-restore behavior. Pass [dryRun]: true (used
  /// by the diagnostics "Restore Preview" action) to compute the same merge
  /// for inspection without touching the cursor at all.
  ///
  /// Returns null if no backup exists yet on Drive. Note: this returns the
  /// merged snapshot for the caller to hydrate into a local cache — it does
  /// not itself write to a local store, since that piece (the message/todo
  /// local cache) is a separate, not-yet-built part of this project.
  Future<BackupSnapshot?> restoreFromBackup({bool dryRun = false}) async {
    try {
      final partnerPubKey = await CryptoService().fetchPartnerPublicKey();
      if (partnerPubKey == null) {
        LogService.log('Backup: partner public key unavailable, cannot restore');
        return null;
      }
      final sharedKey = await CryptoService().getSharedKey(partnerPubKey);

      // Try both sources (not "Drive, then local only if Drive fails") and
      // use whichever is actually newer — a local-only write can happen
      // when Drive was down/full on a given day, so Drive isn't always the
      // freshest copy just because it's reachable. Comparing each
      // snapshot's own generatedAt (written by this class at merge time)
      // rather than file/cloud-provider modified-time metadata avoids any
      // clock-skew ambiguity between Drive's server timestamp and the
      // device's filesystem timestamp — both generatedAt values come from
      // the same DateTime.now() call site. Local read is on-device/cheap,
      // so trying both unconditionally (not just as a fallback) is worth it
      // for the freshness guarantee.
      final driveBackup = await _downloadAndDecrypt(sharedKey);
      final localBackup = await _downloadAndDecryptFromLocalFolder(sharedKey);

      BackupSnapshot? backup;
      if (driveBackup != null && localBackup != null) {
        final useLocal = localBackup.generatedAt.isAfter(driveBackup.generatedAt);
        backup = useLocal ? localBackup : driveBackup;
        LogService.log('Backup: restoring from ${useLocal ? "local folder" : "Drive"} '
            '(local: ${localBackup.generatedAt}, Drive: ${driveBackup.generatedAt})');
      } else {
        backup = driveBackup ?? localBackup;
        if (backup != null) {
          LogService.log(
              'Backup: restoring from ${driveBackup != null ? "Drive" : "local folder"} '
              '(only source available)');
        }
      }
      if (backup == null) {
        LogService.log('Backup: no existing backup found to restore (Drive or local)');
        return null;
      }

      // Independent reads — run concurrently rather than sequentially. This
      // runs on the fresh-install/PIN-restore path, shown with a blocking
      // "Restoring your history..." dialog, so wall-clock time here is
      // directly user-visible.
      final liveResults = await Future.wait([
        _firestore.fetchTodosSince(coupleId, null),
        _firestore.fetchCommentsSince(null),
        _firestore.fetchMessagesSince(coupleId, null),
        _firestore.fetchStickyNotesSince(coupleId, null),
      ]);
      final liveTodos = _sanitizeList(liveResults[0]);
      final liveComments = _sanitizeList(liveResults[1]);
      final liveMessages = _sanitizeList(liveResults[2]);
      final liveStickyNotes = _sanitizeList(liveResults[3]);

      final merged = backup.copyWith(
        todos: mergeDelta(backup.todos, liveTodos),
        comments: mergeDelta(backup.comments, liveComments),
        messages: mergeDelta(backup.messages, liveMessages),
        stickyNotes: mergeDelta(backup.stickyNotes, liveStickyNotes),
      );

      if (!dryRun) {
        final now = DateTime.now();
        await _cursorStore.save(BackupCursor(
          todosSyncedAt: maxTimestampField(liveTodos, 'updatedAt') ?? now,
          commentsSyncedAt: maxTimestampField(liveComments, 'createdAt') ?? now,
          messagesSyncedAt: maxTimestampField(liveMessages, 'updatedAt') ?? now,
          stickyNotesSyncedAt: maxTimestampField(liveStickyNotes, 'updatedAt') ?? now,
          deletionsSyncedAt: now,
          lastBackupAt: now,
        ));
        await _applyPreferencesLocally(backup.preferences);
      }

      LogService.log(
          'Backup: restore${dryRun ? " (dry run)" : ""} merged ${merged.todos.length} todos, ${merged.messages.length} messages, ${merged.stickyNotes.length} sticky notes');
      return merged;
    } catch (e) {
      LogService.log('Backup Error: restore failed: $e');
      return null;
    }
  }

  // ── Internal helpers ─────────────────────────────────────────────────────

  Future<BackupSnapshot?> _downloadAndDecrypt(SecretKey sharedKey) async {
    final bytes = await _drive.downloadBytesByName(BackupConfig.latestBackupFileName);
    if (bytes == null) return null;
    return _decodeSnapshot(bytes, sharedKey);
  }

  /// Same encrypted-JSON format as Drive's copy (see _writeLocalBackup),
  /// just read from Documents/Tether/backups instead. Always available —
  /// the folder is auto-created via MediaStore, no user setup step to have
  /// skipped.
  ///
  /// Deliberately never throws: this is one of two independent sources
  /// restoreFromBackup() tries, and a truncated/corrupt/wrong-key local
  /// file must not take down a restore that already has a perfectly good
  /// Drive backup in hand — it should just be treated the same as "no
  /// local backup exists" and fall through to Drive.
  Future<BackupSnapshot?> _downloadAndDecryptFromLocalFolder(SecretKey sharedKey) async {
    try {
      final bytes = await _localFolder.readBackup(BackupConfig.latestBackupFileName);
      if (bytes == null) return null;
      LogService.log('Backup: restoring from local folder (Documents/Tether/backups)');
      return await _decodeSnapshot(bytes, sharedKey);
    } catch (e) {
      LogService.log('Backup: local folder backup unreadable, ignoring it: $e');
      return null;
    }
  }

  Future<BackupSnapshot> _decodeSnapshot(Uint8List bytes, SecretKey sharedKey) async {
    final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final plainBytes = await CryptoService().decryptBytes(envelope, sharedKey);
    final json = jsonDecode(utf8.decode(plainBytes)) as Map<String, dynamic>;
    return BackupSnapshot.fromJson(json);
  }

  /// Pure encryption step, split out from the actual upload so the exact
  /// same encrypted bytes can be written to both Drive and the local SAF
  /// backup folder without encrypting twice.
  Future<Uint8List> _encrypt(BackupSnapshot snapshot, SecretKey sharedKey) async {
    final plainBytes = utf8.encode(jsonEncode(snapshot.toJson()));
    final envelope =
        await CryptoService().encryptBytes(Uint8List.fromList(plainBytes), sharedKey);
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  /// Best-effort local-first copy, independent of whether Drive itself
  /// succeeds — this is what makes the local folder useful even when Drive
  /// is full/offline. Takes already-encrypted bytes (same ones uploaded to
  /// Drive, computed once by the caller) so the snapshot is never encrypted
  /// twice per run. Same filename as Drive's own "latest" file — unlike
  /// Drive, there's no separate pending/rotate dance locally; Drive already
  /// covers historical generations, so the local copy is deliberately just
  /// the single newest snapshot.
  Future<bool> _writeLocalBackup(Uint8List encryptedBytes) async {
    try {
      final ok = await _localFolder.writeBackup(
          BackupConfig.latestBackupFileName, encryptedBytes);
      if (ok) LogService.log('Backup: local copy written (${encryptedBytes.length} bytes)');
      return ok;
    } catch (e) {
      LogService.log('Backup: local copy failed: $e');
      return false;
    }
  }

  Future<({bool ok, String detail})> _verifyIntegrity(BackupSnapshot merged) async {
    final liveTodoCount = await _firestore.countTodos(coupleId);
    final liveMessageCount = await _firestore.countMessages(coupleId);
    final liveStickyNoteCount = await _firestore.countStickyNotes(coupleId);

    // ">=" rather than "==": once old messages start getting purged from
    // Firestore, the backup will legitimately hold more than what's live.
    // It should never hold fewer than what's currently live, though.
    final todosOk = merged.todos.length >= liveTodoCount;
    final messagesOk = merged.messages.length >= liveMessageCount;
    final stickyNotesOk = merged.stickyNotes.length >= liveStickyNoteCount;

    // Previously this only returned a bool, so a failure logged as
    // "Integrity check failed, aborting promotion" with no numbers —
    // undiagnosable after the fact (was it one collection short by one
    // row, or a real gap?). Detail string always built (not just on
    // failure) so a future investigation can also compare successful runs.
    final detail = 'todos: ${merged.todos.length}/$liveTodoCount, '
        'messages: ${merged.messages.length}/$liveMessageCount, '
        'stickyNotes: ${merged.stickyNotes.length}/$liveStickyNoteCount';

    return (ok: todosOk && messagesOk && stickyNotesOk, detail: detail);
  }

  Future<void> _rotateGenerations() async {
    final latestId = await _drive.findFileIdByName(BackupConfig.latestBackupFileName);
    var occupiedGenerations = 0;
    for (var i = 1; i <= BackupConfig.maxBackupGenerations; i++) {
      final id = await _drive.findFileIdByName(BackupConfig.backupGenerationFileName(i));
      if (id == null) break;
      occupiedGenerations = i;
    }

    final plan = computeRotationPlan(
      latestOccupied: latestId != null,
      occupiedGenerations: occupiedGenerations,
      maxGenerations: BackupConfig.maxBackupGenerations,
      generationFileName: BackupConfig.backupGenerationFileName,
      latestFileName: BackupConfig.latestBackupFileName,
    );

    for (final op in plan) {
      if (op.type == RotationOpType.delete) {
        await _drive.deleteFileByName(op.from);
      } else {
        await _drive.renameFileByName(op.from, op.to!);
      }
    }
  }

  /// Uploads any locally-saved Snaps that haven't reached Drive yet, and
  /// deletes any Drive Snap files whose local copy was removed since the
  /// last run. This used to happen immediately on save/download/delete —
  /// moved here so Snap actions never themselves trigger a Drive round
  /// trip; they're just batched into the same backup cycle as everything
  /// else, and reuse whatever access token this run already fetched.
  Future<void> _syncSnaps() async {
    final storage = LocalStorageService();

    final pendingUploads = await storage.pendingUploadSnaps();
    for (final snap in pendingUploads) {
      try {
        final bytes = await File(snap.imagePath).readAsBytes();
        final driveFileId = await _drive.uploadSnap(bytes, 'snap_${snap.id}.png');
        if (driveFileId != null) {
          await storage.updateDriveFileId(snap.id, driveFileId);
        }
        // Write-through to the local folder too — same batched-into-
        // backup-cycle reasoning as the Drive upload above, and this is
        // what makes a snap recoverable after uninstall/reinstall even if
        // Drive was never reached (space, network) for this particular run.
        await _localFolder.writeSnap('snap_${snap.id}.png', bytes, 'image/png');
      } catch (e) {
        LogService.log('Backup: snap upload failed for ${snap.id}: $e');
      }
    }

    final pendingDeletions = await storage.pendingDeletionDriveFileIds();
    for (final driveFileId in pendingDeletions) {
      try {
        final ok = await _drive.deleteFile(driveFileId);
        if (ok) await storage.clearPendingDeletion(driveFileId);
      } catch (e) {
        LogService.log('Backup: snap delete failed for $driveFileId: $e');
      }
    }

    // Recovers snaps that exist on Drive but not locally — the case on
    // every fresh install, since local storage is wiped on reinstall but
    // Drive isn't. Matches by the snap_{id}.png filename uploadSnap() uses.
    var recovered = 0;
    try {
      final driveFiles = await _drive.listSnapFiles();
      final localIds = await storage.localSnapIds();
      final pendingDeletionIds = pendingDeletions.toSet();
      for (final file in driveFiles) {
        final match = RegExp(r'^snap_(\d+)\.png$').firstMatch(file.name);
        if (match == null) continue;
        final id = match.group(1)!;
        if (localIds.contains(id)) continue;
        // Don't resurrect a snap the user just deleted locally and is
        // waiting on this very run to remove from Drive too.
        if (pendingDeletionIds.contains(file.id)) continue;
        try {
          final bytes = await _drive.downloadFileBytes(file.id);
          if (bytes != null) {
            await storage.saveRecoveredSnap(id, bytes, file.id);
            recovered++;
          }
        } catch (e) {
          LogService.log('Backup: snap recovery failed for ${file.name}: $e');
        }
      }
    } catch (e) {
      LogService.log('Backup: snap recovery listing failed: $e');
    }

    if (pendingUploads.isNotEmpty || pendingDeletions.isNotEmpty || recovered > 0) {
      LogService.log(
          'Backup: synced ${pendingUploads.length} snap upload(s), ${pendingDeletions.length} snap deletion(s), $recovered snap(s) recovered from Drive');
    }
  }

  /// Read-only snapshot of backup state for manual verification — what the
  /// local cursor thinks has synced, which generations exist on Drive, and
  /// how the backup's counts compare to what's currently live in Firestore.
  /// Never mutates anything (no promotion, no cursor changes).
  Future<BackupInspection> inspect() async {
    final cursor = await _cursorStore.load();
    final latestId = await _drive.findFileIdByName(BackupConfig.latestBackupFileName);
    final occupied = <int>[];
    for (var i = 1; i <= BackupConfig.maxBackupGenerations; i++) {
      final id = await _drive.findFileIdByName(BackupConfig.backupGenerationFileName(i));
      if (id != null) occupied.add(i);
    }

    final liveTodoCount = await _firestore.countTodos(coupleId);
    final liveMessageCount = await _firestore.countMessages(coupleId);
    final liveStickyNoteCount = await _firestore.countStickyNotes(coupleId);

    int? backupTodoCount, backupMessageCount, backupStickyNoteCount;
    String? error;
    if (latestId != null) {
      try {
        final partnerPubKey = await CryptoService().fetchPartnerPublicKey();
        if (partnerPubKey != null) {
          final sharedKey = await CryptoService().getSharedKey(partnerPubKey);
          final snap = await _downloadAndDecrypt(sharedKey);
          if (snap != null) {
            backupTodoCount = snap.todos.length;
            backupMessageCount = snap.messages.length;
            backupStickyNoteCount = snap.stickyNotes.length;
          }
        }
      } catch (e) {
        error = 'Could not decrypt existing backup for inspection: $e';
      }
    }

    return BackupInspection(
      cursor: cursor,
      latestExists: latestId != null,
      occupiedGenerations: occupied,
      liveTodoCount: liveTodoCount,
      liveMessageCount: liveMessageCount,
      liveStickyNoteCount: liveStickyNoteCount,
      backupTodoCount: backupTodoCount,
      backupMessageCount: backupMessageCount,
      backupStickyNoteCount: backupStickyNoteCount,
      error: error,
    );
  }
}
