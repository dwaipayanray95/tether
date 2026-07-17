package com.theawesomeray.tether

import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.BatteryManager
import android.os.Environment
import android.provider.MediaStore
import androidx.core.app.Person
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.theawesomeray.tether/music"
    private var musicChannel: MethodChannel? = null
    private var musicReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        musicChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        registerMusicReceiver()

        val batteryChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.theawesomeray.tether/battery")
        batteryChannel.setMethodCallHandler { call, result ->
            if (call.method == "getBatteryInfo") {
                val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                val batteryPct = if (level >= 0 && scale > 0) (level * 100 / scale) else -1

                val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL

                val data = mapOf(
                    "batteryLevel" to batteryPct,
                    "isCharging" to isCharging
                )
                result.success(data)
            } else {
                result.notImplemented()
            }
        }

        val shortcutsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.theawesomeray.tether/shortcuts")
        shortcutsChannel.setMethodCallHandler { call, result ->
            if (call.method == "pushConversationShortcut") {
                val shortcutId = call.argument<String>("shortcutId")
                val label = call.argument<String>("label")
                if (shortcutId != null && label != null) {
                    pushConversationShortcut(shortcutId, label)
                    result.success(true)
                } else {
                    result.error("bad_args", "shortcutId and label are required", null)
                }
            } else {
                result.notImplemented()
            }
        }

        val mediaStoreChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.theawesomeray.tether/mediastore")
        mediaStoreChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "writeFile" -> {
                        val relativePath = call.argument<String>("relativePath")!!
                        val fileName = call.argument<String>("fileName")!!
                        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                        val bytes = call.argument<ByteArray>("bytes")!!
                        result.success(mediaStoreWriteFile(relativePath, fileName, mimeType, bytes))
                    }
                    "readFile" -> {
                        val relativePath = call.argument<String>("relativePath")!!
                        val fileName = call.argument<String>("fileName")!!
                        result.success(mediaStoreReadFile(relativePath, fileName))
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("mediastore_error", e.message, null)
            }
        }
    }

    override fun onDestroy() {
        unregisterMusicReceiver()
        super.onDestroy()
    }

    // ── MediaStore: auto-created "Documents/Tether/..." folder ────────────────
    //
    // Deliberately NOT the Storage Access Framework — SAF requires an
    // interactive folder-picker dialog before the app can write anything,
    // every install. MediaStore lets the app silently create and write into
    // a public-but-outside-app-private-storage folder (survives uninstall,
    // same as a SAF-picked folder would) with only a normal one-time
    // permission grant, no picker UI at all. RELATIVE_PATH supports nested
    // segments natively (e.g. "Documents/Tether/backups/") — Android creates
    // every intermediate folder automatically.
    //
    // API 29+ (Android 10, scoped storage): pure MediaStore, no
    // WRITE_EXTERNAL_STORAGE needed for files this app itself creates.
    // API 24-28 (this app's minSdk 24 through Android 9): MediaStore's
    // RELATIVE_PATH column doesn't exist yet, so these fall back to direct
    // File I/O against the legacy public Documents directory instead
    // (requires WRITE_EXTERNAL_STORAGE, requested from the Dart side via
    // permission_handler before these methods are called).

    private fun mediaStoreWriteFile(relativePath: String, fileName: String, mimeType: String, bytes: ByteArray): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return legacyWriteFile(relativePath, fileName, bytes)
        }

        val resolver = contentResolver
        val collection = MediaStore.Files.getContentUri("external")

        val existingUri = findMediaStoreFile(relativePath, fileName)
        if (existingUri != null) {
            return try {
                // openOutputStream can return null (e.g. the row exists but its
                // backing file was removed externally) — that must be reported
                // as a failed write, not a silent no-op success.
                val stream = resolver.openOutputStream(existingUri, "wt") ?: return false
                stream.use { it.write(bytes) }
                true
            } catch (e: Exception) {
                false
            }
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val uri = resolver.insert(collection, values) ?: return false
        return try {
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            true
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            false
        }
    }

    private fun mediaStoreReadFile(relativePath: String, fileName: String): ByteArray? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return legacyReadFile(relativePath, fileName)
        }
        val uri = findMediaStoreFile(relativePath, fileName) ?: return null
        return try {
            contentResolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (e: Exception) {
            null
        }
    }

    private fun findMediaStoreFile(relativePath: String, fileName: String): Uri? {
        val resolver = contentResolver
        val collection = MediaStore.Files.getContentUri("external")
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection = "${MediaStore.MediaColumns.RELATIVE_PATH} = ? AND ${MediaStore.MediaColumns.DISPLAY_NAME} = ?"
        val args = arrayOf(normalizedRelativePath(relativePath), fileName)
        resolver.query(collection, projection, selection, args, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID))
                return ContentUris.withAppendedId(collection, id)
            }
        }
        return null
    }

    private fun normalizedRelativePath(relativePath: String): String =
        if (relativePath.endsWith("/")) relativePath else "$relativePath/"

    // ── Legacy fallback (API 24-28, pre-scoped-storage) ────────────────────

    private fun legacyDir(relativePath: String): File {
        val base = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
        // relativePath already starts with "Documents/..." from the Dart side —
        // strip that prefix since getExternalStoragePublicDirectory(DOCUMENTS)
        // already resolves to the Documents folder itself.
        val trimmed = relativePath.removePrefix("Documents/").removePrefix("Documents").trim('/')
        val dir = if (trimmed.isEmpty()) base else File(base, trimmed)
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun legacyWriteFile(relativePath: String, fileName: String, bytes: ByteArray): Boolean {
        return try {
            val file = File(legacyDir(relativePath), fileName)
            FileOutputStream(file).use { it.write(bytes) }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun legacyReadFile(relativePath: String, fileName: String): ByteArray? {
        return try {
            val file = File(legacyDir(relativePath), fileName)
            if (!file.exists()) null else file.readBytes()
        } catch (e: Exception) {
            null
        }
    }

    // Publishes a long-lived dynamic shortcut tied to a Person. This is what
    // makes a MessagingStyle notification with a matching shortcutId land in
    // Android's "Conversations" section (pinned above regular notifications,
    // like WhatsApp/Instagram DMs) instead of behaving as a plain high-priority
    // alert. Setting importance/priority to max alone does not do this — the
    // shortcut is the actual signal Android checks for conversation grouping.
    private fun pushConversationShortcut(shortcutId: String, label: String) {
        val icon = IconCompat.createWithResource(this, R.mipmap.ic_launcher)

        val person = Person.Builder()
            .setName(label)
            .setIcon(icon)
            .setImportant(true)
            .build()

        val intent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
        }

        val shortcut = ShortcutInfoCompat.Builder(this, shortcutId)
            .setLongLived(true)
            .setShortLabel(label)
            .setIcon(icon)
            .setPerson(person)
            .setIntent(intent)
            .build()

        try {
            ShortcutManagerCompat.pushDynamicShortcut(this, shortcut)
        } catch (e: Exception) {
            // Non-fatal — worst case the notification falls back to a normal
            // high-priority alert instead of a grouped conversation.
        }
    }

    private fun registerMusicReceiver() {
        musicReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent == null) return

                val artist = intent.getStringExtra("artist") ?: ""
                val track = intent.getStringExtra("track") ?: ""
                val album = intent.getStringExtra("album") ?: ""

                // Determine playstate
                var isPlaying = intent.getBooleanExtra("playing", false)
                if (!intent.hasExtra("playing")) {
                    isPlaying = intent.getBooleanExtra("isPlaying", false)
                }
                val action = intent.action
                if (action != null && !intent.hasExtra("playing") && !intent.hasExtra("isPlaying")) {
                    if (action.contains("playstatechanged") || action.contains("playbackstatechanged")) {
                        isPlaying = intent.getBooleanExtra("playing", false) || intent.getBooleanExtra("playstate", false)
                    } else if (action.contains("metachanged") || action.contains("metadatachanged") || action.contains("playback")) {
                        isPlaying = true
                    }
                }

                if (track.isNotEmpty() || artist.isNotEmpty()) {
                    val data = mapOf(
                        "track" to track,
                        "artist" to artist,
                        "album" to album,
                        "isPlaying" to isPlaying
                    )
                    runOnUiThread {
                        musicChannel?.invokeMethod("onMusicChanged", data)
                    }
                }
            }
        }

        val filter = IntentFilter().apply {
            // Apple Music Intents
            addAction("com.apple.android.music.metachanged")
            addAction("com.apple.android.music.playstatechanged")
            addAction("com.apple.android.music.playbackstatechanged")
            addAction("com.apple.android.music.queuechanged")

            // Spotify Intents
            addAction("com.spotify.music.metadatachanged")
            addAction("com.spotify.music.playbackstatechanged")
            addAction("com.spotify.music.queuechanged")

            // YT Music & Google Play Music Intents
            addAction("com.google.android.music.metachanged")
            addAction("com.google.android.music.playstatechanged")
            addAction("com.google.android.music.playbackstatechanged")

            // Standard / Generic Android Music Intents
            addAction("com.android.music.metachanged")
            addAction("com.android.music.playstatechanged")
            addAction("com.android.music.playbackstatechanged")
            addAction("com.android.music.queuechanged")

            // MIUI / local players
            addAction("com.miui.player.metachanged")
            addAction("com.miui.player.playstatechanged")
            addAction("com.htc.music.metachanged")
            addAction("com.sec.android.app.music.metachanged")
            addAction("com.sec.android.app.music.playstatechanged")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(musicReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(musicReceiver, filter)
        }
    }

    private fun unregisterMusicReceiver() {
        musicReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                // ignore
            }
        }
        musicReceiver = null
    }
}
