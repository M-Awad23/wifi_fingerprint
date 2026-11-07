import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../local_survey_database.dart';
import '../services/wifi_scanner.dart';
import 'ar_survey_page.dart';
import 'saved_session_maps_page.dart';

class SurveyHomePage extends StatefulWidget {
  const SurveyHomePage({super.key});

  @override
  State<SurveyHomePage> createState() => _SurveyHomePageState();
}

class _SurveyHomePageState extends State<SurveyHomePage> {
  static const _sensorChannel = EventChannel('wifi_fingerprint/sensors');
  final _sessionController = TextEditingController(text: 'Test Session');
  final _buildingController = TextEditingController();
  final _locationController = TextEditingController();
  List<Map<String, dynamic>> _accessPoints = [];
  bool _isSurveying = false;
  bool _isScanning = false;
  int _scanCount = 0;
  int _savedSensorCount = 0;
  int? _activeSessionId;
  DateTime? _lastScanTime;
  StreamSubscription<dynamic>? _sensorSubscription;
  Map<String, dynamic> _sensorData = {};
  String _deviceModel = '—';

  @override
  void initState() {
    super.initState();
    _sensorSubscription = _sensorChannel.receiveBroadcastStream().listen(
      _onSensorEvent,
    );
  }

  Future<void> _onSensorEvent(dynamic event) async {
    if (!mounted) return;
    final data = Map<String, dynamic>.from(event as Map);
    setState(() {
      _sensorData = data;
      _deviceModel = data['deviceModel']?.toString() ?? _deviceModel;
    });
    final sessionId = _activeSessionId;
    if (!_isSurveying || sessionId == null) return;
    try {
      await LocalSurveyDatabase.instance.saveSensorSample(
        sessionId: sessionId,
        event: data,
      );
      if (mounted) setState(() => _savedSensorCount++);
    } catch (error) {
      _showMessage('Local sensor save failed: $error');
    }
  }

  @override
  void dispose() {
    _sensorSubscription?.cancel();
    _sessionController.dispose();
    _buildingController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _toggleSurvey() async {
    if (_isSurveying) {
      final sessionId = _activeSessionId;
      if (sessionId != null) {
        await LocalSurveyDatabase.instance.stopSession(sessionId);
      }
      if (!mounted) return;
      setState(() {
        _isSurveying = false;
        _activeSessionId = null;
      });
      _showMessage('Survey stopped and saved on this device.');
      return;
    }
    final name = _sessionController.text.trim();
    if (name.isEmpty) return _showMessage('Enter a session name first.');
    try {
      final id = await LocalSurveyDatabase.instance.startSession(
        name: name,
        building: _buildingController.text.trim(),
        deviceModel: _deviceModel,
      );
      if (!mounted) return;
      setState(() {
        _activeSessionId = id;
        _isSurveying = true;
        _savedSensorCount = 0;
        _scanCount = 0;
      });
      _showMessage(
        'Recording locally. Keep the survey running while collecting.',
      );
    } catch (error) {
      _showMessage('Could not start local recording: $error');
    }
  }

  Future<void> _scanWifi() async {
    setState(() => _isScanning = true);
    try {
      final response = await WifiScanner.scanWithResponse();
      final accessPoints = (response['accessPoints'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _accessPoints = accessPoints;
        _scanCount++;
        _lastScanTime = DateTime.now();
      });
      final sessionId = _activeSessionId;
      if (_isSurveying && sessionId != null) {
        await LocalSurveyDatabase.instance.saveScan(
          sessionId: sessionId,
          response: response,
          accessPoints: accessPoints,
          building: _buildingController.text.trim(),
          locationLabel: _locationController.text.trim(),
          sensorData: _sensorData,
          deviceModel: _deviceModel,
        );
        _showMessage('Wi-Fi scan saved locally.');
      }
    } on PlatformException catch (error) {
      _showMessage('Scan failed: ${error.message ?? error.code}');
    } on MissingPluginException {
      _showMessage('Android scanner channel is unavailable.');
    } catch (error) {
      _showMessage('Local scan save failed: $error');
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _exportDatabase() async {
    try {
      final database = await LocalSurveyDatabase.instance.database;
      await database.rawQuery('PRAGMA wal_checkpoint(FULL)');
      final databaseDirectory = await getDatabasesPath();
      final source = File('$databaseDirectory/wifi_fingerprint.db');
      if (!await source.exists()) throw Exception('Database file not found.');
      await WifiScanner.exportDatabase(source.path);
      _showMessage('Database export completed.');
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Database export failed.');
    } catch (error) {
      _showMessage('Database export failed: $error');
    }
  }

  Future<void> _openSessionMaps() async {
    final sessions = await LocalSurveyDatabase.instance.getSessions();
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SavedSessionMapsPage(sessions: sessions),
        ),
      );
    }
  }

  String _timeLabel(DateTime? time) => time == null
      ? '—'
      : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';

  String _formatSensorValue(dynamic value) {
    if (value == null) return 'Waiting for sensor…';
    if (value is List) {
      return value
          .map(
            (item) => item is num ? item.toStringAsFixed(2) : item.toString(),
          )
          .join(', ');
    }
    return value is num ? value.toStringAsFixed(2) : value.toString();
  }

  Widget _field(String label, TextEditingController controller) => SizedBox(
    width: 220,
    child: TextField(
      controller: controller,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Widget _sensorLine(String label, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text(
      '$label: ${_formatSensorValue(value)}',
      style: const TextStyle(fontSize: 12),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('WiFi Fingerprint', style: TextStyle(fontSize: 18)),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _field('Session', _sessionController),
            _field('Building', _buildingController),
            _field('Location label', _locationController),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _toggleSurvey,
              child: Text(_isSurveying ? 'Stop survey' : 'Start survey'),
            ),
            OutlinedButton.icon(
              onPressed: _openSessionMaps,
              icon: const Icon(Icons.map_outlined, size: 16),
              label: const Text('Session maps'),
            ),
            OutlinedButton.icon(
              onPressed: _exportDatabase,
              icon: const Icon(Icons.file_download_outlined, size: 16),
              label: const Text('Export database'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ArSurveyPage())),
              icon: const Icon(Icons.view_in_ar, size: 16),
              label: const Text('AR survey'),
            ),
            Text(
              _isSurveying ? 'Status: Recording locally' : 'Status: Idle',
              style: const TextStyle(fontSize: 13),
            ),
            Text('Scans: $_scanCount', style: const TextStyle(fontSize: 13)),
            Text(
              'Saved sensor samples: $_savedSensorCount',
              style: const TextStyle(fontSize: 13),
            ),
            Text(
              'APs: ${_accessPoints.length}',
              style: const TextStyle(fontSize: 13),
            ),
            Text(
              'Last scan: ${_timeLabel(_lastScanTime)}',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        const Divider(height: 20),
        const Text(
          'Motion sensors',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        Text('Device: $_deviceModel', style: const TextStyle(fontSize: 12)),
        _sensorLine('Accelerometer (m/s²)', _sensorData['accelerometer']),
        _sensorLine('Gyroscope (rad/s)', _sensorData['gyroscope']),
        _sensorLine('Magnetometer (µT)', _sensorData['magnetometer']),
        _sensorLine('Heading (°)', _sensorData['headingDegrees']),
        _sensorLine('Orientation (°)', _sensorData['orientationDegrees']),
        _sensorLine('Sensor timestamp (ns)', _sensorData['timestampNs']),
        const Divider(height: 20),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _isScanning ? null : _scanWifi,
              icon: _isScanning
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_find, size: 16),
              label: Text(_isScanning ? 'Scanning…' : 'Scan Wi-Fi'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => setState(() {
                _accessPoints = [];
                _scanCount = 0;
                _lastScanTime = null;
              }),
              child: const Text('Reset'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                'SSID',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                'BSSID',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            SizedBox(
              width: 76,
              child: Text(
                'RSSI',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            SizedBox(
              width: 78,
              child: Text(
                'MHz',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
        const Divider(height: 8),
        if (_accessPoints.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No scan results.', style: TextStyle(fontSize: 13)),
          )
        else
          ..._accessPoints.map(
            (ap) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      ap['ssid']?.toString().isNotEmpty == true
                          ? ap['ssid'].toString()
                          : '<hidden>',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      ap['bssid']?.toString() ?? '—',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  SizedBox(
                    width: 76,
                    child: Text(
                      '${ap['rssi'] ?? '—'} dBm',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  SizedBox(
                    width: 78,
                    child: Text(
                      ap['frequency']?.toString() ?? '—',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
