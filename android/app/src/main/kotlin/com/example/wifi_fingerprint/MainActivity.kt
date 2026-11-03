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
import android.provider.Settings
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "wifi_fingerprint/scanner"
    private val permissionRequestCode = 4101
    private var pendingScanResult: MethodChannel.Result? = null
    private var receiverRegistered = false
    private var scanStartElapsedUs: Long = 0
    private lateinit var wifiManager: WifiManager
    private lateinit var methodChannel: MethodChannel
    private val handler = Handler(Looper.getMainLooper())

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
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "scanWifi" -> scanWifi(result)
                else -> result.notImplemented()
            }
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
        super.onDestroy()
    }
}
