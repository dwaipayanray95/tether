package com.theawesomeray.tether

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.BatteryManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
    }

    override fun onDestroy() {
        unregisterMusicReceiver()
        super.onDestroy()
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
                val action = intent.action
                if (action != null && !intent.hasExtra("playing")) {
                    if (action.contains("playstatechanged")) {
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
            // Standard / Spotify intent fallbacks
            addAction("com.android.music.metachanged")
            addAction("com.android.music.playstatechanged")
            addAction("com.spotify.music.metadatachanged")
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
