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
