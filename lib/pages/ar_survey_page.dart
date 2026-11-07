import 'dart:math' as math;

import 'package:ar_flutter_plugin_flutterflow/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_session_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/wifi_scanner.dart';

class ArSurveyPage extends StatefulWidget {
  const ArSurveyPage({super.key});

  @override
  State<ArSurveyPage> createState() => _ArSurveyPageState();
}

class _ArSurveyPageState extends State<ArSurveyPage> {
  ARSessionManager? _sessionManager;
  List<Map<String, dynamic>> _accessPoints = [];
  bool _scanning = false;
  String _trackingStatus = 'Move the phone slowly to initialize tracking';

  void _onArViewCreated(
    ARSessionManager sessionManager,
    ARObjectManager objectManager,
    ARAnchorManager anchorManager,
    ARLocationManager locationManager,
  ) {
    _sessionManager = sessionManager;
    sessionManager.onInitialize(
      showFeaturePoints: false,
      showPlanes: false,
      showWorldOrigin: false,
      handleTaps: false,
    );
    objectManager.onInitialize();
    if (mounted) setState(() => _trackingStatus = 'AR tracking active');
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final response = await WifiScanner.scanWithResponse();
      final accessPoints =
          (response['accessPoints'] as List<dynamic>? ?? [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList()
            ..sort(
              (left, right) => ((right['rssi'] as num?) ?? -100).compareTo(
                (left['rssi'] as num?) ?? -100,
              ),
            );
      if (mounted) setState(() => _accessPoints = accessPoints);
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message ?? error.code)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Scan failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  void dispose() {
    _sessionManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AR survey')),
    body: Stack(
      children: [
        ARView(
          onARViewCreated: _onArViewCreated,
          permissionPromptDescription:
              'Camera access is required for AR surveying.',
          permissionPromptButtonText: 'Grant camera access',
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _trackingStatus,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
        const Center(child: Icon(Icons.add, color: Colors.white70, size: 30)),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Nearby access points',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${_accessPoints.length}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: _scanning ? null : _scan,
                      icon: _scanning
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_find, size: 16),
                      label: Text(_scanning ? 'Scanning' : 'Scan'),
                    ),
                  ],
                ),
                if (_accessPoints.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Scan to view nearby Wi-Fi signals.',
                      style: TextStyle(fontSize: 12),
                    ),
                  )
                else
                  SizedBox(
                    height: 150,
                    child: ListView.builder(
                      itemCount: math.min(5, _accessPoints.length),
                      itemBuilder: (context, index) {
                        final ap = _accessPoints[index];
                        final rssi = (ap['rssi'] as num?)?.toInt() ?? -100;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.wifi,
                            color: rssi >= -60
                                ? Colors.green
                                : (rssi >= -75 ? Colors.orange : Colors.grey),
                          ),
                          title: Text(
                            ap['ssid']?.toString().isNotEmpty == true
                                ? ap['ssid'].toString()
                                : 'Hidden network',
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            '${ap['bssid'] ?? ''} · ${ap['frequency'] ?? '—'} MHz',
                            style: const TextStyle(fontSize: 10),
                          ),
                          trailing: Text(
                            '$rssi dBm',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const Text(
                  'AR camera tracking is active; AP direction/position is not inferred from RSSI alone.',
                  style: TextStyle(fontSize: 10, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
