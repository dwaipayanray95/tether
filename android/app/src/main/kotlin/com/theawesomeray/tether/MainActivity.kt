package com.theawesomeray.tether

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.BatteryManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.core.app.Person
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.theawesomeray.tether/music"
    private var musicChannel: MethodChannel? = null
    private var musicReceiver: BroadcastReceiver? = null

    private val COMPASS_CHANNEL = "com.theawesomeray.tether/compass"
    private var sensorManager: SensorManager? = null
    private var rotationSensor: Sensor? = null
    private var magneticSensor: Sensor? = null
    private var accelerometerSensor: Sensor? = null
    
    private val rMat = FloatArray(9)
    private val orientation = FloatArray(3)
    private var lastAccelerometer = FloatArray(3)
    private var lastMagnetometer = FloatArray(3)
    private var lastAccelerometerSet = false
    private var lastMagnetometerSet = false
    
    private var compassEventSink: EventChannel.EventSink? = null
    
    private val compassListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent?) {
            if (event == null) return
            var azimuth = 0f
            
            if (event.sensor.type == Sensor.TYPE_ROTATION_VECTOR) {
                SensorManager.getRotationMatrixFromVector(rMat, event.values)
                azimuth = Math.toDegrees(SensorManager.getOrientation(rMat, orientation)[0].toDouble()).toFloat()
            } else {
                if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
                    System.arraycopy(event.values, 0, lastAccelerometer, 0, event.values.size)
                    lastAccelerometerSet = true
                } else if (event.sensor.type == Sensor.TYPE_MAGNETIC_FIELD) {
                    System.arraycopy(event.values, 0, lastMagnetometer, 0, event.values.size)
                    lastMagnetometerSet = true
                }
                if (lastAccelerometerSet && lastMagnetometerSet) {
                    SensorManager.getRotationMatrix(rMat, null, lastAccelerometer, lastMagnetometer)
                    azimuth = Math.toDegrees(SensorManager.getOrientation(rMat, orientation)[0].toDouble()).toFloat()
                }
            }
            
            azimuth = (azimuth + 360) % 360
            
            runOnUiThread {
                compassEventSink?.success(azimuth.toDouble())
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

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

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        rotationSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        if (rotationSensor == null) {
            magneticSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
            accelerometerSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        }
        
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, COMPASS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    compassEventSink = events
                    registerCompass()
                }

                override fun onCancel(arguments: Any?) {
                    unregisterCompass()
                    compassEventSink = null
                }
            }
        )
    }

    private fun registerCompass() {
        rotationSensor?.let {
            sensorManager?.registerListener(compassListener, it, SensorManager.SENSOR_DELAY_UI)
        } ?: run {
            sensorManager?.registerListener(compassListener, magneticSensor, SensorManager.SENSOR_DELAY_UI)
            sensorManager?.registerListener(compassListener, accelerometerSensor, SensorManager.SENSOR_DELAY_UI)
        }
    }
    
    private fun unregisterCompass() {
        sensorManager?.unregisterListener(compassListener)
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
