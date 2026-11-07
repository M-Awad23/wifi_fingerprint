import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalSurveyDatabase {
  LocalSurveyDatabase._();
  static final LocalSurveyDatabase instance = LocalSurveyDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final root = await getDatabasesPath();
    _database = await openDatabase(
      p.join(root, 'wifi_fingerprint.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE survey_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_name TEXT NOT NULL,
            building TEXT,
            started_at_utc TEXT NOT NULL,
            ended_at_utc TEXT,
            device_model TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE sensor_samples (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            sensor_type TEXT NOT NULL,
            sensor_timestamp_ns INTEGER NOT NULL,
            elapsed_realtime_ns INTEGER,
            recorded_at_utc TEXT NOT NULL,
            x REAL, y REAL, z REAL,
            heading_degrees REAL,
            orientation_x REAL, orientation_y REAL, orientation_z REAL,
            FOREIGN KEY(session_id) REFERENCES survey_sessions(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE scan_batches (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            building TEXT,
            location_label TEXT,
            received_at_utc TEXT NOT NULL,
            scan_started_elapsed_us INTEGER,
            heading_degrees REAL,
            device_model TEXT,
            FOREIGN KEY(session_id) REFERENCES survey_sessions(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE access_point_observations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            scan_batch_id INTEGER NOT NULL,
            ssid TEXT,
            bssid TEXT,
            rssi INTEGER,
            frequency_mhz INTEGER,
            device_timestamp_us INTEGER,
            FOREIGN KEY(scan_batch_id) REFERENCES scan_batches(id)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_sensor_session_time ON sensor_samples(session_id, sensor_timestamp_ns)',
        );
        await db.execute(
          'CREATE INDEX idx_scans_session_time ON scan_batches(session_id, received_at_utc)',
        );
        await db.execute(
          'CREATE INDEX idx_ap_batch ON access_point_observations(scan_batch_id)',
        );
      },
    );
    return _database!;
  }

  Future<int> startSession({
    required String name,
    String? building,
    String? deviceModel,
  }) async {
    final db = await database;
    return db.insert('survey_sessions', {
      'session_name': name,
      'building': building,
      'started_at_utc': DateTime.now().toUtc().toIso8601String(),
      'device_model': deviceModel,
    });
  }

  Future<void> stopSession(int id) async {
    final db = await database;
    await db.update(
      'survey_sessions',
      {'ended_at_utc': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> saveSensorSample({
    required int sessionId,
    required Map<String, dynamic> event,
  }) async {
    final values = (event['values'] as List?)?.cast<num>();
    final orientation = (event['orientationDegrees'] as List?)?.cast<num>();
    final db = await database;
    await db.insert('sensor_samples', {
      'session_id': sessionId,
      'sensor_type': event['sensor'],
      'sensor_timestamp_ns': event['timestampNs'],
      'elapsed_realtime_ns': event['elapsedRealtimeNs'],
      'recorded_at_utc': DateTime.now().toUtc().toIso8601String(),
      'x': values != null && values.isNotEmpty ? values[0].toDouble() : null,
      'y': values != null && values.length > 1 ? values[1].toDouble() : null,
      'z': values != null && values.length > 2 ? values[2].toDouble() : null,
      'heading_degrees': event['headingDegrees'],
      'orientation_x': orientation != null && orientation.isNotEmpty
          ? orientation[0].toDouble()
          : null,
      'orientation_y': orientation != null && orientation.length > 1
          ? orientation[1].toDouble()
          : null,
      'orientation_z': orientation != null && orientation.length > 2
          ? orientation[2].toDouble()
          : null,
    });
  }

  Future<void> saveScan({
    required int sessionId,
    required Map<String, dynamic> response,
    required List<Map<String, dynamic>> accessPoints,
    required String? building,
    required String? locationLabel,
    required Map<String, dynamic> sensorData,
    required String? deviceModel,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final batchId = await txn.insert('scan_batches', {
        'session_id': sessionId,
        'building': building,
        'location_label': locationLabel,
        'received_at_utc': DateTime.now().toUtc().toIso8601String(),
        'scan_started_elapsed_us': response['scanStartedElapsedRealtimeUs'],
        'heading_degrees': sensorData['headingDegrees'],
        'device_model': deviceModel,
      });
      final batch = txn.batch();
      for (final ap in accessPoints) {
        batch.insert('access_point_observations', {
          'scan_batch_id': batchId,
          'ssid': ap['ssid'],
          'bssid': ap['bssid'],
          'rssi': ap['rssi'],
          'frequency_mhz': ap['frequency'],
          'device_timestamp_us': ap['timestamp'],
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> getSessions() async {
    final db = await database;
    return db.query('survey_sessions', orderBy: 'started_at_utc DESC');
  }

  Future<List<Map<String, dynamic>>> getSensorSamples(int sessionId) async {
    final db = await database;
    return db.query(
      'sensor_samples',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'sensor_timestamp_ns ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getScanBatches(int sessionId) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT sb.id, sb.received_at_utc, sb.heading_degrees, sb.location_label,
             ap.ssid, ap.bssid, ap.rssi, ap.frequency_mhz
      FROM scan_batches sb
      LEFT JOIN access_point_observations ap ON ap.scan_batch_id = sb.id
      WHERE sb.session_id = ?
      ORDER BY sb.received_at_utc ASC, ap.rssi DESC
    ''',
      [sessionId],
    );
  }

  Future<Map<String, int>> getSessionCounts(int sessionId) async {
    final db = await database;
    final sensors =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM sensor_samples WHERE session_id = ?',
            [sessionId],
          ),
        ) ??
        0;
    final scans =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM scan_batches WHERE session_id = ?',
            [sessionId],
          ),
        ) ??
        0;
    return {'sensorSamples': sensors, 'scanBatches': scans};
  }
}
