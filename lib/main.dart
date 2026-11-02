import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const WiFiFingerprintApp());
}

class WiFiFingerprintApp extends StatelessWidget {
  const WiFiFingerprintApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WiFi Fingerprint',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF176B87),
        ),
        useMaterial3: true,
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

List<Map<String, dynamic>> _accessPoints = [];
bool _isScanning = false;

Future<void> _scanWifi() async {
  setState(() {
    _isScanning = true;
  });

  try {
    final result =
        await _wifiChannel.invokeMethod<List<dynamic>>('scanWifi');

    final accessPoints = (result ?? []).map((item) {
      return Map<String, dynamic>.from(item as Map);
    }).toList();

    setState(() {
      _accessPoints = accessPoints;
      _scanCount++;
    });
  } on PlatformException catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Wi-Fi scan failed: ${e.message}')),
    );
  } finally {
    setState(() {
      _isScanning = false;
    });
  }
}
  final _sessionController = TextEditingController();
  final _buildingController = TextEditingController();
  final _locationController = TextEditingController();

  bool _isSurveying = false;
  int _scanCount = 0;

  @override
  void dispose() {
    _sessionController.dispose();
    _buildingController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _toggleSurvey() {
    if (!_isSurveying && _sessionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a session name before starting.'),
        ),
      );
      return;
    }

    setState(() {
      _isSurveying = !_isSurveying;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isSurveying
              ? 'Survey session started.'
              : 'Survey session stopped.',
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon),
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi Fingerprint'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Indoor Survey',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Collect Wi-Fi fingerprints for indoor positioning.',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 24),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Survey Session',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _sessionController,
                      label: 'Session name',
                      hint: 'e.g. JU Library - Survey 1',
                      icon: Icons.assignment_outlined,
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _buildingController,
                      label: 'Building (optional)',
                      hint: 'e.g. Library',
                      icon: Icons.business_outlined,
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _locationController,
                      label: 'Location label (optional)',
                      hint: 'e.g. First floor - Entrance',
                      icon: Icons.place_outlined,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _toggleSurvey,
                        icon: Icon(
                          _isSurveying ? Icons.stop : Icons.play_arrow,
                        ),
                        label: Text(
                          _isSurveying ? 'Stop Survey' : 'Start Survey',
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor:
                              _isSurveying ? Colors.red : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Collection Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Nearby Access Points',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isScanning ? null : _scanWifi,
            icon: _isScanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find),
            label: Text(_isScanning ? 'Scanning...' : 'Scan Wi-Fi'),
          ),
        ),
        const SizedBox(height: 12),
        if (_accessPoints.isEmpty)
          const Text('No scan results yet.')
        else
          ..._accessPoints.map((ap) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.wifi),
              title: Text(ap['ssid']?.toString() ?? 'Hidden network'),
              subtitle: Text(
                'BSSID: ${ap['bssid']}  •  ${ap['frequency']} MHz',
              ),
              trailing: Text('${ap['rssi']} dBm'),
            );
          }),
      ],
    ),
  ),
),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          _isSurveying
                              ? Icons.circle
                              : Icons.circle_outlined,
                          color: _isSurveying
                              ? Colors.green
                              : Colors.grey,
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isSurveying ? 'Survey active' : 'Not surveying',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.wifi, size: 20),
                        const SizedBox(width: 8),
                        Text('Scans collected: $_scanCount'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text(
                      'Nearby access points will appear here once the '
                      'Android scanner is connected.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _scanCount = 0;
                });
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Reset scan counter'),
            ),
          ],
        ),
      ),
    );
  }
}