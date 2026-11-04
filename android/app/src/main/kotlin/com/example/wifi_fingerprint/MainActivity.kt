package com.example.wifi_fingerprint

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.EventChannel
import android.provider.Settings
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), SensorEventListener {
    private val channelName = "wifi_fingerprint/scanner"
    private val permissionRequestCode = 4101
    private val exportRequestCode = 4102
    private var exportPath: String? = null
    private var exportResult: MethodChannel.Result? = null
    private var pendingScanResult: MethodChannel.Result? = null
    private var receiverRegistered = false
    private var scanStartElapsedUs: Long = 0
    private lateinit var wifiManager: WifiManager
    private lateinit var methodChannel: MethodChannel
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var sensorManager: SensorManager
    private var sensorSink: EventChannel.EventSink? = null
    private val sensorValues = mutableMapOf<String, FloatArray>()
    private var sensorsRegistered = false

    private val scanTimeout = Runnable {
        finishScan(resultsUpdated = false, timedOut = true)
    }

    private val scanReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != WifiManager.SCAN_RESULTS_AVAILABLE_ACTION) return
            val updated = intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false)
            handler.removeCallbacks(scanTimeout)
            finishScan(resultsUpdated = updated, timedOut = false)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "wifi_fingerprint/sensors").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sensorSink = events; registerSensors() }
            override fun onCancel(arguments: Any?) { sensorSink = null; unregisterSensors() }
        })
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "scanWifi" -> scanWifi(result)
                "exportDatabase" -> { exportPath = call.argument<String>("path"); exportResult = result; val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type = "application/octet-stream"; putExtra(Intent.EXTRA_TITLE, "wifi_fingerprint.db") }; startActivityForResult(intent, exportRequestCode) }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Document picker callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != exportRequestCode) return
        val result = exportResult
        exportResult = null
        if (result == null) return
        if (resultCode != RESULT_OK || data?.data == null) { result.success(false); return }
        try {
            val source = java.io.File(exportPath ?: error("Database path unavailable"))
            contentResolver.openOutputStream(data.data!!).use { output ->
                requireNotNull(output)
                source.inputStream().use { input -> input.copyTo(output) }
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("EXPORT_FAILED", e.message, null)
        }
    }

    private fun scanWifi(result: MethodChannel.Result) {
        if (pendingScanResult != null) {
            result.error("SCAN_IN_PROGRESS", "A Wi-Fi scan is already in progress.", null)
            return
        }
        if (!hasLocationPermission()) {
            pendingScanResult = result
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.ACCESS_FINE_LOCATION), permissionRequestCode)
            return
        }
        if (!isLocationEnabled()) {
            result.error("LOCATION_DISABLED", "Enable Location services to allow Android Wi-Fi scan results.", null)
            return
        }
        if (!wifiManager.isWifiEnabled) {
            result.error("WIFI_DISABLED", "Enable Wi-Fi and try again.", null)
            return
        }

        pendingScanResult = result
        scanStartElapsedUs = SystemClock.elapsedRealtimeNanos() / 1000L
        registerScanReceiver()
        val started = try {
            wifiManager.startScan()
        } catch (e: SecurityException) {
            finishWithError("PERMISSION_DENIED", "Android denied Wi-Fi scan access.")
            return
        }

        if (!started) {
            finishWithError("SCAN_THROTTLED", "Android did not start a new scan (likely throttled). Wait before retrying.")
        } else {
            handler.postDelayed(scanTimeout, 12000)
        }
    }

    private fun finishScan(resultsUpdated: Boolean, timedOut: Boolean) {
        val result = pendingScanResult ?: return
        pendingScanResult = null
        unregisterScanReceiver()
        try {
            val scanResults = wifiManager.scanResults
            val fresh = resultsUpdated && scanResults.isNotEmpty() &&
                scanResults.all { it.timestamp > scanStartElapsedUs }
            if (!fresh) {
                result.error(
                    if (timedOut) "SCAN_TIMEOUT" else "STALE_SCAN_RESULTS",
                    "No fresh Wi-Fi scan results were received. Cached results were discarded.",
                    null
                )
                return
            }
            val accessPoints = scanResults.filter { it.timestamp > scanStartElapsedUs }.map { scan ->
                mapOf(
                    "ssid" to scan.SSID,
                    "bssid" to scan.BSSID,
                    "rssi" to scan.level,
                    "frequency" to scan.frequency,
                    "timestamp" to scan.timestamp
                )
            }
            result.success(mapOf(
                "isFresh" to true,
                "scanStartedElapsedRealtimeUs" to scanStartElapsedUs,
                "receivedAtUtc" to System.currentTimeMillis(),
                "accessPoints" to accessPoints
            ))
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "Permission is required to read scan results.", null)
        }
    }

    private fun finishWithError(code: String, message: String) {
        handler.removeCallbacks(scanTimeout)
        unregisterScanReceiver()
        val result = pendingScanResult
        pendingScanResult = null
        result?.error(code, message, null)
    }

    private fun registerScanReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(scanReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(scanReceiver, filter)
        }
        receiverRegistered = true
    }

    private fun unregisterScanReceiver() {
        if (!receiverRegistered) return
        try { unregisterReceiver(scanReceiver) } catch (_: IllegalArgumentException) {}
        receiverRegistered = false
    }

    private fun registerSensors() {
        if (sensorsRegistered) return
        listOf(Sensor.TYPE_ACCELEROMETER, Sensor.TYPE_GYROSCOPE, Sensor.TYPE_MAGNETIC_FIELD).forEach { type ->
            sensorManager.getDefaultSensor(type)?.let { sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
        }
        sensorsRegistered = true
    }
    private fun unregisterSensors() { if (sensorsRegistered) { sensorManager.unregisterListener(this); sensorsRegistered = false } }
    override fun onSensorChanged(event: SensorEvent) {
        val key = when (event.sensor.type) { Sensor.TYPE_ACCELEROMETER -> "accelerometer"; Sensor.TYPE_GYROSCOPE -> "gyroscope"; Sensor.TYPE_MAGNETIC_FIELD -> "magnetometer"; else -> return }
        sensorValues[key] = event.values.copyOf()
        val a = sensorValues["accelerometer"]; val m = sensorValues["magnetometer"]
        var heading: Float? = null; var orientation: List<Float>? = null
        if (a != null && m != null) {
            val r = FloatArray(9); val i = FloatArray(9)
            if (SensorManager.getRotationMatrix(r, i, a, m)) {
                val angles = FloatArray(3); SensorManager.getOrientation(r, angles)
                heading = (Math.toDegrees(angles[0].toDouble()).toFloat() + 360f) % 360f
                orientation = angles.map { Math.toDegrees(it.toDouble()).toFloat() }
            }
        }
        sensorSink?.success(mapOf("sensor" to key, "timestampNs" to event.timestamp, "elapsedRealtimeNs" to SystemClock.elapsedRealtimeNanos(), "values" to event.values.toList(), "accelerometer" to sensorValues["accelerometer"]?.toList(), "gyroscope" to sensorValues["gyroscope"]?.toList(), "magnetometer" to sensorValues["magnetometer"]?.toList(), "headingDegrees" to heading, "orientationDegrees" to orientation, "deviceModel" to (Build.MANUFACTURER + " " + Build.MODEL)))
    }
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun hasLocationPermission(): Boolean =
        ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    private fun isLocationEnabled(): Boolean {
        val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) manager.isLocationEnabled
        else {
            @Suppress("DEPRECATION")
            Settings.Secure.getInt(contentResolver, Settings.Secure.LOCATION_MODE, 0) != Settings.Secure.LOCATION_MODE_OFF
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return
        val result = pendingScanResult ?: return
        pendingScanResult = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            scanWifi(result)
        } else {
            result.error("PERMISSION_DENIED", "Location permission is required to read nearby Wi-Fi scan results.", null)
        }
    }

    override fun onDestroy() {
        handler.removeCallbacks(scanTimeout)
        unregisterScanReceiver()
        pendingScanResult = null
        unregisterSensors()
        super.onDestroy()
    }
}
