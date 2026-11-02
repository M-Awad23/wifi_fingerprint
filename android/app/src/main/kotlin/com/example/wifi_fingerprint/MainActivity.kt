package com.example.wifi_fingerprint

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "wifi_fingerprint/scanner"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {
                "scanWifi" -> {
                    // Temporary mock data for emulator development.
                    // We'll replace this with WifiManager scan results.
                    val accessPoints = listOf(
                        mapOf(
                            "ssid" to "Campus_WiFi",
                            "bssid" to "02:11:22:33:44:01",
                            "rssi" to -48,
                            "frequency" to 2412
                        ),
                        mapOf(
                            "ssid" to "Campus_Guest",
                            "bssid" to "02:11:22:33:44:02",
                            "rssi" to -67,
                            "frequency" to 2437
                        ),
                        mapOf(
                            "ssid" to "Router_5G",
                            "bssid" to "02:11:22:33:44:03",
                            "rssi" to -76,
                            "frequency" to 5180
                        )
                    )

                    result.success(accessPoints)
                }

                else -> result.notImplemented()
            }
        }
    }
}
