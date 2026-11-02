import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const WiFiFingerprintApp());

class WiFiFingerprintApp extends StatelessWidget {
  const WiFiFingerprintApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WiFi Fingerprint',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: Colors.black,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
      ),
      home: const SurveyHomePage(),
    );
  }
}

class SurveyHomePage extends StatefulWidget {
  const SurveyHomePage({super.key});

  @override
  State<SurveyHomePage> createState() => _SurveyHomePageState();
}

class _SurveyHomePageState extends State<SurveyHomePage> {
  static const MethodChannel _wifiChannel =
      MethodChannel('wifi_fingerprint/scanner');

  final _sessionController = TextEditingController(text: 'Test Session');
  final _buildingController = TextEditingController();
  final _locationController = TextEditingController();

  List<Map<String, dynamic>> _accessPoints = [];
  bool _isSurveying = false;
  bool _isScanning = false;
  int _scanCount = 0;
  DateTime? _lastScanTime;

  @override
  void dispose() {
    _sessionController.dispose();
    _buildingController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _scanWifi() async {
    setState(() => _isScanning = true);

    try {
      final result =
          await _wifiChannel.invokeMethod<List<dynamic>>('scanWifi');
      final accessPoints = (result ?? []).map((item) {
        return Map<String, dynamic>.from(item as Map);
      }).toList();

      if (!mounted) return;
      setState(() {
        _accessPoints = accessPoints;
        _scanCount++;
        _lastScanTime = DateTime.now();
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan failed: ${e.message ?? e.code}')),
      );
    } on MissingPluginException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Android scanner channel is unavailable.')),
      );
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _toggleSurvey() {
    if (!_isSurveying && _sessionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a session name first.')),
      );
      return;
    }

    setState(() => _isSurveying = !_isSurveying);
  }

  void _reset() {
    setState(() {
      _accessPoints = [];
      _scanCount = 0;
      _lastScanTime = null;
    });
  }

  String _timeLabel(DateTime? time) {
    if (time == null) return '—';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  Widget _field(String label, TextEditingController controller) {
    return SizedBox(
      width: 220,
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              Text(
                _isSurveying ? 'Status: Collecting' : 'Status: Idle',
                style: const TextStyle(fontSize: 13),
              ),
              Text('Scans: $_scanCount', style: const TextStyle(fontSize: 13)),
              Text('APs: ${_accessPoints.length}',
                  style: const TextStyle(fontSize: 13)),
              Text('Last scan: ${_timeLabel(_lastScanTime)}',
                  style: const TextStyle(fontSize: 13)),
            ],
          ),
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
                onPressed: _reset,
                child: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              Expanded(flex: 3, child: Text('SSID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Expanded(flex: 4, child: Text('BSSID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              SizedBox(width: 76, child: Text('RSSI', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              SizedBox(width: 78, child: Text('MHz', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            ],
          ),
          const Divider(height: 8),
          if (_accessPoints.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No scan results.', style: TextStyle(fontSize: 13)),
            )
          else
            ..._accessPoints.map((ap) => Padding(
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
                        child: Text(ap['bssid']?.toString() ?? '—',
                            style: const TextStyle(fontSize: 12)),
                      ),
                      SizedBox(
                        width: 76,
                        child: Text('${ap['rssi'] ?? '—'} dBm',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 12)),
                      ),
                      SizedBox(
                        width: 78,
                        child: Text(ap['frequency']?.toString() ?? '—',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}
