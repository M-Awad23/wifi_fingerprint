import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'local_survey_database.dart';

void main() => runApp(const WiFiFingerprintApp());

class WiFiFingerprintApp extends StatelessWidget {
  const WiFiFingerprintApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'WiFi Fingerprint', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: const ColorScheme.light(primary: Colors.black, surface: Colors.white), scaffoldBackgroundColor: Colors.white, appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0)),
    home: const SurveyHomePage(),
  );
}

class SurveyHomePage extends StatefulWidget {
  const SurveyHomePage({super.key});
  @override
  State<SurveyHomePage> createState() => _SurveyHomePageState();
}

class _SurveyHomePageState extends State<SurveyHomePage> {
  static const MethodChannel _wifiChannel = MethodChannel('wifi_fingerprint/scanner');
  static const EventChannel _sensorChannel = EventChannel('wifi_fingerprint/sensors');
  final _sessionController = TextEditingController(text: 'Test Session');
  final _buildingController = TextEditingController();
  final _locationController = TextEditingController();
  List<Map<String, dynamic>> _accessPoints = [];
  bool _isSurveying = false, _isScanning = false;
  int _scanCount = 0, _savedSensorCount = 0;
  int? _activeSessionId;
  DateTime? _lastScanTime;
  StreamSubscription<dynamic>? _sensorSubscription;
  Map<String, dynamic> _sensorData = {};
  String _deviceModel = '—';

  @override
  void initState() {
    super.initState();
    _sensorSubscription = _sensorChannel.receiveBroadcastStream().listen((event) async {
      if (!mounted) return;
      final data = Map<String, dynamic>.from(event as Map);
      setState(() {
        _sensorData = data;
        _deviceModel = data['deviceModel']?.toString() ?? _deviceModel;
      });
      final sessionId = _activeSessionId;
      if (_isSurveying && sessionId != null) {
        try {
          await LocalSurveyDatabase.instance.saveSensorSample(sessionId: sessionId, event: data);
          if (mounted) setState(() => _savedSensorCount++);
        } catch (e) {
          if (mounted) _showMessage('Local sensor save failed: $e');
        }
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sensorSubscription?.cancel();
    _sessionController.dispose(); _buildingController.dispose(); _locationController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleSurvey() async {
    if (_isSurveying) {
      final id = _activeSessionId;
      if (id != null) await LocalSurveyDatabase.instance.stopSession(id);
      if (!mounted) return;
      setState(() { _isSurveying = false; _activeSessionId = null; });
      _showMessage('Survey stopped and saved on this device.');
      return;
    }
    final name = _sessionController.text.trim();
    if (name.isEmpty) { _showMessage('Enter a session name first.'); return; }
    try {
      final id = await LocalSurveyDatabase.instance.startSession(name: name, building: _buildingController.text.trim(), deviceModel: _deviceModel);
      if (!mounted) return;
      setState(() { _activeSessionId = id; _isSurveying = true; _savedSensorCount = 0; _scanCount = 0; });
      _showMessage('Recording locally. Keep the survey running while collecting.');
    } catch (e) { _showMessage('Could not start local recording: $e'); }
  }

  Future<void> _scanWifi() async {
    setState(() => _isScanning = true);
    try {
      final result = await _wifiChannel.invokeMethod<Map<dynamic, dynamic>>('scanWifi');
      if (result == null || result['isFresh'] != true) throw PlatformException(code: 'STALE_SCAN_RESULTS', message: 'No fresh scan data received.');
      final rawAps = result['accessPoints'] as List<dynamic>? ?? [];
      final aps = rawAps.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      if (!mounted) return;
      setState(() { _accessPoints = aps; _scanCount++; _lastScanTime = DateTime.now(); });
      final sessionId = _activeSessionId;
      if (_isSurveying && sessionId != null) {
        await LocalSurveyDatabase.instance.saveScan(sessionId: sessionId, response: Map<String, dynamic>.from(result), accessPoints: aps, building: _buildingController.text.trim(), locationLabel: _locationController.text.trim(), sensorData: _sensorData, deviceModel: _deviceModel);
        _showMessage('Wi-Fi scan saved locally.');
      }
    } on PlatformException catch (e) { _showMessage('Scan failed: ${e.message ?? e.code}'); }
      on MissingPluginException { _showMessage('Android scanner channel is unavailable.'); }
      catch (e) { _showMessage('Local scan save failed: $e'); }
    finally { if (mounted) setState(() => _isScanning = false); }
  }

  void _reset() {
    setState(() { _accessPoints = []; _scanCount = 0; _lastScanTime = null; });
  }

  String _timeLabel(DateTime? time) => time == null ? '—' : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';

  Widget _sensorLine(String label, dynamic value) {
    String format(dynamic v) {
      if (v == null) return 'Waiting for sensor…';
      if (v is List) return v.map((x) => x is num ? x.toStringAsFixed(2) : x.toString()).join(', ');
      if (v is num) return v.toStringAsFixed(2);
      return v.toString();
    }
    return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('$label: ${format(value)}', style: const TextStyle(fontSize: 12)));
  }

  Future<void> _exportDatabase() async {
    try {
      final db = await LocalSurveyDatabase.instance.database;
      await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
      final dbPath = await getDatabasesPath();
      final source = File('$dbPath/wifi_fingerprint.db');
      if (!await source.exists()) throw Exception('Database file not found.');
      await const MethodChannel('wifi_fingerprint/scanner').invokeMethod('exportDatabase', {'path': source.path});
      _showMessage('Database export completed.');
    } on PlatformException catch (e) {
      _showMessage(e.message ?? 'Database export failed.');
    } catch (e) {
      _showMessage('Database export failed: $e');
    }
  }

  Future<void> _openSessionMaps() async {
    final sessions = await LocalSurveyDatabase.instance.getSessions();
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SavedSessionMapsPage(sessions: sessions)));
  }

  Widget _field(String label, TextEditingController controller) => SizedBox(width: 220, child: TextField(controller: controller, style: const TextStyle(fontSize: 13), decoration: InputDecoration(labelText: label, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), border: const OutlineInputBorder())));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('WiFi Fingerprint', style: TextStyle(fontSize: 18)), bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1))),
    body: ListView(padding: const EdgeInsets.all(12), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [_field('Session', _sessionController), _field('Building', _buildingController), _field('Location label', _locationController)]),
      const SizedBox(height: 10),
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 8, children: [
        OutlinedButton(onPressed: _toggleSurvey, child: Text(_isSurveying ? 'Stop survey' : 'Start survey')),
        OutlinedButton.icon(onPressed: _openSessionMaps, icon: const Icon(Icons.map_outlined, size: 16), label: const Text('Session maps')),
        OutlinedButton.icon(onPressed: _exportDatabase, icon: const Icon(Icons.file_download_outlined, size: 16), label: const Text('Export database')),
        OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ArSurveyPage())), icon: const Icon(Icons.view_in_ar, size: 16), label: const Text('AR survey')),
        Text(_isSurveying ? 'Status: Recording locally' : 'Status: Idle', style: const TextStyle(fontSize: 13)),
        Text('Scans: $_scanCount', style: const TextStyle(fontSize: 13)),
        Text('Saved sensor samples: $_savedSensorCount', style: const TextStyle(fontSize: 13)),
        Text('APs: ${_accessPoints.length}', style: const TextStyle(fontSize: 13)),
        Text('Last scan: ${_timeLabel(_lastScanTime)}', style: const TextStyle(fontSize: 13)),
      ]),
      const Divider(height: 20),
      const Text('Motion sensors', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      Text('Device: $_deviceModel', style: const TextStyle(fontSize: 12)),
      _sensorLine('Accelerometer (m/s²)', _sensorData['accelerometer']),
      _sensorLine('Gyroscope (rad/s)', _sensorData['gyroscope']),
      _sensorLine('Magnetometer (µT)', _sensorData['magnetometer']),
      _sensorLine('Heading (°)', _sensorData['headingDegrees']),
      _sensorLine('Orientation (°)', _sensorData['orientationDegrees']),
      _sensorLine('Sensor timestamp (ns)', _sensorData['timestampNs']),
      const Divider(height: 20),
      Row(children: [
        OutlinedButton.icon(onPressed: _isScanning ? null : _scanWifi, icon: _isScanning ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_find, size: 16), label: Text(_isScanning ? 'Scanning…' : 'Scan Wi-Fi')),
        const SizedBox(width: 8), OutlinedButton(onPressed: _reset, child: const Text('Reset')),
      ]),
      const SizedBox(height: 10),
      const Row(children: [
        Expanded(flex: 3, child: Text('SSID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
        Expanded(flex: 4, child: Text('BSSID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
        SizedBox(width: 76, child: Text('RSSI', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
        SizedBox(width: 78, child: Text('MHz', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
      ]),
      const Divider(height: 8),
      if (_accessPoints.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No scan results.', style: TextStyle(fontSize: 13)))
      else ..._accessPoints.map((ap) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
        Expanded(flex: 3, child: Text(ap['ssid']?.toString().isNotEmpty == true ? ap['ssid'].toString() : '<hidden>', style: const TextStyle(fontSize: 12))),
        Expanded(flex: 4, child: Text(ap['bssid']?.toString() ?? '—', style: const TextStyle(fontSize: 12))),
        SizedBox(width: 76, child: Text('${ap['rssi'] ?? '—'} dBm', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
        SizedBox(width: 78, child: Text(ap['frequency']?.toString() ?? '—', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
      ]))),
    ]),
  );
}


class SavedSessionMapsPage extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;
  const SavedSessionMapsPage({super.key, required this.sessions});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Saved session maps')),
    body: sessions.isEmpty
      ? const Center(child: Text('No saved survey sessions yet.'))
      : ListView.builder(
          itemCount: sessions.length,
          itemBuilder: (context, index) {
            final session = sessions[index];
            final name = session['session_name']?.toString() ?? 'Session';
            final started = session['started_at_utc']?.toString() ?? '';
            final building = session['building']?.toString() ?? '';
            return ListTile(
              leading: const Icon(Icons.route),
              title: Text(name),
              subtitle: Text([building, started].where((s) => s.isNotEmpty).join(' • ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SessionTrajectoryPage(session: session))),
            );
          }),
  );
}

class SessionTrajectoryPage extends StatefulWidget {
  final Map<String, dynamic> session;
  const SessionTrajectoryPage({super.key, required this.session});
  @override
  State<SessionTrajectoryPage> createState() => _SessionTrajectoryPageState();
}

class _SessionTrajectoryPageState extends State<SessionTrajectoryPage> {
  late Future<_SurveyMapData> _mapFuture;
  int _sampleCount = 0;
  int _stepCount = 0;
  int? _selectedScan;

  @override
  void initState() {
    super.initState();
    _mapFuture = _buildMapData();
  }

  Future<_SurveyMapData> _buildMapData() async {
    final sessionId = widget.session['id'] as int;
    final rows = await LocalSurveyDatabase.instance.getSensorSamples(sessionId);
    final scanRows = await LocalSurveyDatabase.instance.getScanBatches(sessionId);
    _sampleCount = rows.length;
    final points = <Offset>[Offset.zero];
    final stepTimes = <DateTime>[DateTime.tryParse(rows.isNotEmpty ? rows.first['recorded_at_utc'].toString() : '') ?? DateTime.now()];
    var lastPeakNs = 0;
    var previousMagnitude = 0.0;
    var rising = false;
    var heading = 0.0;
    const gravity = 9.80665;
    for (final row in rows) {
      if (row['heading_degrees'] is num) heading = (row['heading_degrees'] as num).toDouble();
      if (row['sensor_type'] != 'accelerometer') continue;
      final x = (row['x'] as num?)?.toDouble() ?? 0;
      final y = (row['y'] as num?)?.toDouble() ?? 0;
      final z = (row['z'] as num?)?.toDouble() ?? 0;
      final magnitude = math.sqrt(x*x + y*y + z*z);
      final timestamp = (row['sensor_timestamp_ns'] as num).toInt();
      final above = magnitude > gravity + 1.15;
      if (above && !rising && previousMagnitude <= magnitude &&
          (lastPeakNs == 0 || timestamp - lastPeakNs > 320000000)) {
        lastPeakNs = timestamp;
        rising = true;
        _stepCount++;
        const stepLength = 0.65;
        final radians = heading * math.pi / 180.0;
        final previous = points.last;
        points.add(Offset(previous.dx + stepLength * math.sin(radians),
            previous.dy + stepLength * math.cos(radians)));
        stepTimes.add(DateTime.tryParse(row['recorded_at_utc'].toString()) ?? stepTimes.last);
      }
      if (!above) rising = false;
      previousMagnitude = magnitude;
    }

    final scansById = <int, _ScanMarker>{};
    for (final row in scanRows) {
      final id = (row['id'] as num).toInt();
      final scanTime = DateTime.tryParse(row['received_at_utc']?.toString() ?? '');
      if (scanTime == null) continue;
      var nearest = 0;
      var best = double.infinity;
      for (var i = 0; i < stepTimes.length; i++) {
        final delta = stepTimes[i].difference(scanTime).inMilliseconds.abs().toDouble();
        if (delta < best) { best = delta; nearest = i; }
      }
      final ap = <Map<String, dynamic>>[];
      if (row['bssid'] != null) ap.add(Map<String, dynamic>.from(row));
      final marker = scansById.putIfAbsent(id, () => _ScanMarker(id: id, time: scanTime, position: points[nearest], aps: []));
      if (ap.isNotEmpty) marker.aps.add(ap.first);
    }
    return _SurveyMapData(points: points, scans: scansById.values.toList());
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.session['session_name']?.toString() ?? 'Session';
    return Scaffold(
      appBar: AppBar(title: Text('$name · survey map')),
      body: FutureBuilder<_SurveyMapData>(
        future: _mapFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Could not build map: ${snapshot.error}'));
          final data = snapshot.data!;
          _ScanMarker? selected;
          for (final scan in data.scans) { if (scan.id == _selectedScan) selected = scan; }
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Text('Origin (0,0) • $_stepCount steps • ${data.scans.length} scans', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Expanded(child: Container(
                width: double.infinity,
                decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(8)),
                child: data.points.length < 2
                  ? const Center(child: Text('Walk while recording to build the path.'))
                  : CustomPaint(painter: SurveyMapPainter(data.points, data.scans, _selectedScan)),
              )),
              const SizedBox(height: 8),
              const Text('Green = start  •  Blue = path  •  Orange = Wi-Fi scan  •  Rings = signal estimate', style: TextStyle(fontSize: 11)),
              if (selected != null) ...[
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: Text('Scan ${selected.id} · ${selected.time.toLocal()} · ${selected.aps.length} APs', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                SizedBox(height: 90, child: ListView.builder(itemCount: selected.aps.length, itemBuilder: (context, i) {
                  final ap = selected.aps[i];
                  return ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(ap['ssid']?.toString().isNotEmpty == true ? ap['ssid'].toString() : 'Hidden network', style: const TextStyle(fontSize: 12)), subtitle: Text('${ap['bssid']}  •  ${ap['rssi']} dBm  •  ${ap['frequency_mhz']} MHz', style: const TextStyle(fontSize: 11)));
                })),
              ],
              SizedBox(height: 80, child: ListView.builder(
                scrollDirection: Axis.horizontal, itemCount: data.scans.length,
                itemBuilder: (context, i) {
                  final scan = data.scans[i];
                  return Padding(padding: const EdgeInsets.only(right: 6), child: OutlinedButton(
                    onPressed: () => setState(() => _selectedScan = scan.id),
                    style: OutlinedButton.styleFrom(backgroundColor: _selectedScan == scan.id ? Colors.orange.shade50 : null),
                    child: Text('Scan ${scan.id}\n${scan.aps.length} APs', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                  ));
                })),
            ]),
          );
        }),
    );
  }
}

class _SurveyMapData {
  final List<Offset> points;
  final List<_ScanMarker> scans;
  _SurveyMapData({required this.points, required this.scans});
}

class _ScanMarker {
  final int id;
  final DateTime time;
  final Offset position;
  final List<Map<String, dynamic>> aps;
  _ScanMarker({required this.id, required this.time, required this.position, required this.aps});
}

class SurveyMapPainter extends CustomPainter {
  final List<Offset> points;
  final List<_ScanMarker> scans;
  final int? selectedScan;
  SurveyMapPainter(this.points, this.scans, this.selectedScan);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final all = [...points, ...scans.map((s) => s.position)];
    final minX = all.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
    final maxX = all.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
    final minY = all.map((p) => p.dy).reduce(math.min);
    final maxY = all.map((p) => p.dy).reduce(math.max);
    final spanX = math.max(1.0, (maxX-minX).abs()).toDouble();
    final spanY = math.max(1.0, (maxY-minY).abs()).toDouble();
    const pad = 30.0;
    final scale = math.max(0.1, math.min((size.width-2*pad)/spanX, (size.height-2*pad)/spanY)).toDouble();
    Offset transform(Offset p) => Offset(pad+(p.dx-minX)*scale, size.height-pad-(p.dy-minY)*scale);
    final path = Path()..moveTo(transform(points.first).dx, transform(points.first).dy);
    for (final point in points.skip(1)) { final q = transform(point); path.lineTo(q.dx, q.dy); }
    canvas.drawPath(path, Paint()..color=Colors.blue..strokeWidth=3..style=PaintingStyle.stroke..strokeCap=StrokeCap.round..strokeJoin=StrokeJoin.round);
    canvas.drawCircle(transform(points.first), 6, Paint()..color=Colors.green);
    canvas.drawRect(Rect.fromCenter(center:transform(points.last),width:10,height:10), Paint()..color=Colors.red);
    for (final scan in scans) {
      final p = transform(scan.position);
      final strongest = scan.aps.map((a) => (a['rssi'] as num?)?.toInt() ?? -100).fold<int>(-100, (a, b) => a > b ? a : b);
      // Visual-only rough RSSI range: stronger signals get smaller rings.
      final radiusMeters = math.max(1.0, math.min(8.0, math.pow(10, (-strongest - 35) / 30).toDouble()));
      final radius = math.max(5.0, radiusMeters * scale);
      canvas.drawCircle(p, radius, Paint()..color=Colors.orange.withOpacity(0.12)..style=PaintingStyle.fill);
      canvas.drawCircle(p, radius, Paint()..color=Colors.orange.withOpacity(0.55)..style=PaintingStyle.stroke..strokeWidth=1);
      canvas.drawCircle(p, selectedScan == scan.id ? 7 : 5, Paint()..color=selectedScan == scan.id ? Colors.deepOrange : Colors.orange);
    }
  }

  @override
  bool shouldRepaint(covariant SurveyMapPainter oldDelegate) => oldDelegate.points != points || oldDelegate.scans != scans || oldDelegate.selectedScan != selectedScan;
}


class ArSurveyPage extends StatefulWidget {
  const ArSurveyPage({super.key});
  @override
  State<ArSurveyPage> createState() => _ArSurveyPageState();
}
class _ArSurveyPageState extends State<ArSurveyPage> {
  static const MethodChannel _wifiChannel = MethodChannel('wifi_fingerprint/scanner');
  ARSessionManager? _sessionManager;
  List<Map<String, dynamic>> _accessPoints = [];
  bool _scanning = false;
  String _trackingStatus = 'Move the phone slowly to initialize tracking';
  void _onArViewCreated(ARSessionManager sessionManager, ARObjectManager objectManager, ARAnchorManager anchorManager, ARLocationManager locationManager) {
    _sessionManager = sessionManager;
    sessionManager.onInitialize(showFeaturePoints: false, showPlanes: false, showWorldOrigin: false, handleTaps: false);
    objectManager.onInitialize();
    if (mounted) setState(() => _trackingStatus = 'AR tracking active');
  }
  Future<void> _scan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final result = await _wifiChannel.invokeMethod<Map<dynamic, dynamic>>('scanWifi');
      if (result == null || result['isFresh'] != true) throw PlatformException(code: 'STALE_SCAN_RESULTS', message: 'No fresh scan data received.');
      final raw = result['accessPoints'] as List<dynamic>? ?? [];
      final aps = raw.map((item) => Map<String, dynamic>.from(item as Map)).toList()
        ..sort((a, b) => ((b['rssi'] as num?) ?? -100).compareTo((a['rssi'] as num?) ?? -100));
      if (mounted) setState(() => _accessPoints = aps);
    } on PlatformException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan failed: $e')));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }
  @override
  void dispose() { _sessionManager?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AR survey')),
    body: Stack(children: [
      ARView(onARViewCreated: _onArViewCreated, permissionPromptDescription: 'Camera access is required for AR surveying.', permissionPromptButtonText: 'Grant camera access'),
      Positioned(top: 12, left: 12, right: 12, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.62), borderRadius: BorderRadius.circular(8)),
        child: Text(_trackingStatus, style: const TextStyle(color: Colors.white, fontSize: 12)),
      )),
      const Center(child: Icon(Icons.add, color: Colors.white70, size: 30)),
      Positioned(left: 12, right: 12, bottom: 12, child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.94), borderRadius: BorderRadius.circular(12)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Expanded(child: Text('Nearby access points', style: TextStyle(fontWeight: FontWeight.w600))),
            Text('${_accessPoints.length}', style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(onPressed: _scanning ? null : _scan,
              icon: _scanning ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_find, size: 16),
              label: Text(_scanning ? 'Scanning' : 'Scan')),
          ]),
          if (_accessPoints.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Scan to view nearby Wi-Fi signals.', style: TextStyle(fontSize: 12)))
          else SizedBox(height: 150, child: ListView.builder(
            itemCount: math.min(5, _accessPoints.length),
            itemBuilder: (context, index) {
              final ap = _accessPoints[index];
              final rssi = (ap['rssi'] as num?)?.toInt() ?? -100;
              return ListTile(dense: true, contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.wifi, color: rssi >= -60 ? Colors.green : (rssi >= -75 ? Colors.orange : Colors.grey)),
                title: Text(ap['ssid']?.toString().isNotEmpty == true ? ap['ssid'].toString() : 'Hidden network', style: const TextStyle(fontSize: 13)),
                subtitle: Text('${ap['bssid'] ?? ''} · ${ap['frequency'] ?? '—'} MHz', style: const TextStyle(fontSize: 10)),
                trailing: Text('$rssi dBm', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)));
            })),
          const Text('AR camera tracking is active; AP direction/position is not inferred from RSSI alone.', style: TextStyle(fontSize: 10, color: Colors.black54)),
        ]),
      )),
    ]),
  );
}
