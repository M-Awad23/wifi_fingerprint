import 'package:flutter/material.dart';

import '../models/survey_map_data.dart';
import '../services/trajectory_builder.dart';
import '../widgets/survey_map_painter.dart';

class SavedSessionMapsPage extends StatelessWidget {
  const SavedSessionMapsPage({super.key, required this.sessions});

  final List<Map<String, dynamic>> sessions;

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
                subtitle: Text(
                  [
                    building,
                    started,
                  ].where((value) => value.isNotEmpty).join(' • '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SessionTrajectoryPage(session: session),
                  ),
                ),
              );
            },
          ),
  );
}

class SessionTrajectoryPage extends StatefulWidget {
  const SessionTrajectoryPage({super.key, required this.session});

  final Map<String, dynamic> session;

  @override
  State<SessionTrajectoryPage> createState() => _SessionTrajectoryPageState();
}

class _SessionTrajectoryPageState extends State<SessionTrajectoryPage> {
  late final Future<SurveyMapData> _mapFuture;
  int? _selectedScan;

  @override
  void initState() {
    super.initState();
    _mapFuture = const TrajectoryBuilder().build(widget.session['id'] as int);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.session['session_name']?.toString() ?? 'Session';
    return Scaffold(
      appBar: AppBar(title: Text('$name · survey map')),
      body: FutureBuilder<SurveyMapData>(
        future: _mapFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not build map: ${snapshot.error}'),
            );
          }
          final data = snapshot.requireData;
          ScanMarker? selected;
          for (final scan in data.scans) {
            if (scan.id == _selectedScan) selected = scan;
          }
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(
                  'Origin (0,0) • ${data.stepCount} steps • ${data.scans.length} scans',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: data.points.length < 2
                        ? const Center(
                            child: Text(
                              'Walk while recording to build the path.',
                            ),
                          )
                        : CustomPaint(
                            painter: SurveyMapPainter(
                              data.points,
                              data.scans,
                              _selectedScan,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Green = start  •  Blue = path  •  Orange = Wi-Fi scan  •  Rings = signal estimate',
                  style: TextStyle(fontSize: 11),
                ),
                if (selected != null) _SelectedScanDetails(scan: selected),
                SizedBox(
                  height: 80,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: data.scans.length,
                    itemBuilder: (context, index) {
                      final scan = data.scans[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: OutlinedButton(
                          onPressed: () =>
                              setState(() => _selectedScan = scan.id),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _selectedScan == scan.id
                                ? Colors.orange.shade50
                                : null,
                          ),
                          child: Text(
                            'Scan ${scan.id}\n${scan.accessPoints.length} APs',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SelectedScanDetails extends StatelessWidget {
  const _SelectedScanDetails({required this.scan});

  final ScanMarker scan;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Scan ${scan.id} · ${scan.time.toLocal()} · ${scan.accessPoints.length} APs',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ),
      SizedBox(
        height: 90,
        child: ListView.builder(
          itemCount: scan.accessPoints.length,
          itemBuilder: (context, index) {
            final ap = scan.accessPoints[index];
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                ap['ssid']?.toString().isNotEmpty == true
                    ? ap['ssid'].toString()
                    : 'Hidden network',
                style: const TextStyle(fontSize: 12),
              ),
              subtitle: Text(
                '${ap['bssid']}  •  ${ap['rssi']} dBm  •  ${ap['frequency_mhz']} MHz',
                style: const TextStyle(fontSize: 11),
              ),
            );
          },
        ),
      ),
    ],
  );
}
