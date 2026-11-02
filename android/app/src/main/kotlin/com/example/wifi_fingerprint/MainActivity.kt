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
    private lateinit var wifiManager: WifiManager
    private lateinit var methodChannel: MethodChannel
    private val handler = Handler(Looper.getMainLooper())

    private val scanTimeout = Runnable {
        finishScan(withCachedResults = true)
    }

    private val scanReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == WifiManager.SCAN_RESULTS_AVAILABLE_ACTION) {
                handler.removeCallbacks(scanTimeout)
                finishScan(withCachedResults = true)
            }
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
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
                permissionRequestCode
            )
            return
        }

        if (!isLocationEnabled()) {
            result.error(
                "LOCATION_DISABLED",
                "Enable Location services to allow Android Wi-Fi scan results.",
                null
            )
            return
        }

        if (!wifiManager.isWifiEnabled) {
            result.error("WIFI_DISABLED", "Enable Wi-Fi and try again.", null)
            return
        }

        pendingScanResult = result
        registerScanReceiver()

        val scanStarted = try {
            wifiManager.startScan()
        } catch (e: SecurityException) {
            finishWithError("PERMISSION_DENIED", "Android denied Wi-Fi scan access.")
            return
        }

        // Android may throttle scans. If a fresh scan cannot start, return the
        // latest available results rather than leaving the UI spinning.
        if (!scanStarted) {
            handler.postDelayed(scanTimeout, 700)
        } else {
            handler.postDelayed(scanTimeout, 12000)
        }
    }

    private fun finishScan(withCachedResults: Boolean) {
        val result = pendingScanResult ?: return
        pendingScanResult = null
        unregisterScanReceiver()

        try {
            val accessPoints = if (withCachedResults) {
                wifiManager.scanResults.map { scan ->
                    mapOf(
                        "ssid" to scan.SSID,
                        "bssid" to scan.BSSID,
                        "rssi" to scan.level,
                        "frequency" to scan.frequency,
                        "timestamp" to scan.timestamp
                    )
                }
            } else {
                emptyList<Map<String, Any>>()
            }
            result.success(accessPoints)
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
        try {
            unregisterReceiver(scanReceiver)
        } catch (_: IllegalArgumentException) {
        }
        receiverRegistered = false
    }

    private fun hasLocationPermission(): Boolean =
        ActivityCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

    private fun isLocationEnabled(): Boolean {
        val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            locationManager.isLocationEnabled
        } else {
            @Suppress("DEPRECATION")
            Settings.Secure.getInt(contentResolver, Settings.Secure.LOCATION_MODE, 0) !=
                Settings.Secure.LOCATION_MODE_OFF
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return

        val result = pendingScanResult
        pendingScanResult = null
        if (result == null) return

        if (grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            // Return to Flutter so the user can tap Scan again after granting.
            result.error("PERMISSION_GRANTED", "Permission granted. Tap Scan Wi-Fi again.", null)
        } else {
            result.error(
                "PERMISSION_DENIED",
                "Location permission is required to read nearby Wi-Fi scan results.",
                null
            )
        }
    }

    override fun onDestroy() {
        handler.removeCallbacks(scanTimeout)
        unregisterScanReceiver()
        pendingScanResult = null
        super.onDestroy()
    }
}
