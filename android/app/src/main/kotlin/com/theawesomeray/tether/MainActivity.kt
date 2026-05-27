package com.theawesomeray.tether

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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

        registerReceiver(musicReceiver, filter)
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
