import 'package:flutter/services.dart';

class WifiScanner {
  WifiScanner._();

  static const _channel = MethodChannel('wifi_fingerprint/scanner');

  static Future<Map<String, dynamic>> scanWithResponse() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'scanWifi',
    );
    if (result == null || result['isFresh'] != true) {
      throw PlatformException(
        code: 'STALE_SCAN_RESULTS',
        message: 'No fresh scan data received.',
      );
    }
    return Map<String, dynamic>.from(result);
  }

  static Future<void> exportDatabase(String path) =>
      _channel.invokeMethod<void>('exportDatabase', {'path': path});
}
