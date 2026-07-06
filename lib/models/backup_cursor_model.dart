/// Per-collection "last synced at" timestamps, persisted on-device.
///
/// Drives incremental backup runs: each collection is fetched with
/// `where updatedAt > cursor` instead of re-reading the whole collection
/// every run. Advance a field only after its data has been successfully
/// merged into the backup.
class BackupCursor {
  final DateTime? messagesSyncedAt;
  final DateTime? todosSyncedAt;
  final DateTime? commentsSyncedAt;
  final DateTime? stickyNotesSyncedAt;
  final DateTime? profileSyncedAt;
  final DateTime? deletionsSyncedAt;
  final DateTime? lastBackupAt;

  const BackupCursor({
    this.messagesSyncedAt,
    this.todosSyncedAt,
    this.commentsSyncedAt,
    this.stickyNotesSyncedAt,
    this.profileSyncedAt,
    this.deletionsSyncedAt,
    this.lastBackupAt,
  });

  factory BackupCursor.fromJson(Map<String, dynamic> json) => BackupCursor(
        messagesSyncedAt: _parse(json['messagesSyncedAt']),
        todosSyncedAt: _parse(json['todosSyncedAt']),
        commentsSyncedAt: _parse(json['commentsSyncedAt']),
        stickyNotesSyncedAt: _parse(json['stickyNotesSyncedAt']),
        profileSyncedAt: _parse(json['profileSyncedAt']),
        deletionsSyncedAt: _parse(json['deletionsSyncedAt']),
        lastBackupAt: _parse(json['lastBackupAt']),
      );

  static DateTime? _parse(dynamic v) =>
      v == null ? null : DateTime.parse(v as String);

  Map<String, dynamic> toJson() => {
        'messagesSyncedAt': messagesSyncedAt?.toIso8601String(),
        'todosSyncedAt': todosSyncedAt?.toIso8601String(),
        'commentsSyncedAt': commentsSyncedAt?.toIso8601String(),
        'stickyNotesSyncedAt': stickyNotesSyncedAt?.toIso8601String(),
        'profileSyncedAt': profileSyncedAt?.toIso8601String(),
        'deletionsSyncedAt': deletionsSyncedAt?.toIso8601String(),
        'lastBackupAt': lastBackupAt?.toIso8601String(),
      };

  BackupCursor copyWith({
    DateTime? messagesSyncedAt,
    DateTime? todosSyncedAt,
    DateTime? commentsSyncedAt,
    DateTime? stickyNotesSyncedAt,
    DateTime? profileSyncedAt,
    DateTime? deletionsSyncedAt,
    DateTime? lastBackupAt,
  }) =>
      BackupCursor(
        messagesSyncedAt: messagesSyncedAt ?? this.messagesSyncedAt,
        todosSyncedAt: todosSyncedAt ?? this.todosSyncedAt,
        commentsSyncedAt: commentsSyncedAt ?? this.commentsSyncedAt,
        stickyNotesSyncedAt: stickyNotesSyncedAt ?? this.stickyNotesSyncedAt,
        profileSyncedAt: profileSyncedAt ?? this.profileSyncedAt,
        deletionsSyncedAt: deletionsSyncedAt ?? this.deletionsSyncedAt,
        lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      );
}
