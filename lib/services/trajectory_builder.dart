import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../local_survey_database.dart';
import '../models/survey_map_data.dart';

class TrajectoryBuilder {
  static const _gravity = 9.80665;
  static const _stepThreshold = 1.15;
  static const _minimumStepIntervalNs = 320000000;
  static const _stepLengthMeters = 0.65;

  const TrajectoryBuilder();

  Future<SurveyMapData> build(int sessionId) async {
    final sensorRows = await LocalSurveyDatabase.instance.getSensorSamples(
      sessionId,
    );
    final scanRows = await LocalSurveyDatabase.instance.getScanBatches(
      sessionId,
    );
    final points = <Offset>[Offset.zero];
    final stepTimes = <DateTime>[
      DateTime.tryParse(
            sensorRows.isNotEmpty
                ? sensorRows.first['recorded_at_utc'].toString()
                : '',
          ) ??
          DateTime.now(),
    ];
    var lastPeakNs = 0;
    var previousMagnitude = 0.0;
    var rising = false;
    var heading = 0.0;
    var stepCount = 0;

    for (final row in sensorRows) {
      if (row['heading_degrees'] is num) {
        heading = (row['heading_degrees'] as num).toDouble();
      }
      if (row['sensor_type'] != 'accelerometer') continue;
      final x = (row['x'] as num?)?.toDouble() ?? 0;
      final y = (row['y'] as num?)?.toDouble() ?? 0;
      final z = (row['z'] as num?)?.toDouble() ?? 0;
      final magnitude = math.sqrt(x * x + y * y + z * z);
      final timestamp = (row['sensor_timestamp_ns'] as num?)?.toInt() ?? 0;
      final aboveThreshold = magnitude > _gravity + _stepThreshold;
      if (aboveThreshold &&
          !rising &&
          previousMagnitude <= magnitude &&
          (lastPeakNs == 0 ||
              timestamp - lastPeakNs > _minimumStepIntervalNs)) {
        lastPeakNs = timestamp;
        rising = true;
        stepCount++;
        final radians = heading * math.pi / 180.0;
        final previous = points.last;
        points.add(
          Offset(
            previous.dx + _stepLengthMeters * math.sin(radians),
            previous.dy + _stepLengthMeters * math.cos(radians),
          ),
        );
        stepTimes.add(
          DateTime.tryParse(row['recorded_at_utc'].toString()) ??
              stepTimes.last,
        );
      }
      if (!aboveThreshold) rising = false;
      previousMagnitude = magnitude;
    }

    final scansById = <int, ScanMarker>{};
    for (final row in scanRows) {
      final id = (row['id'] as num).toInt();
      final scanTime = DateTime.tryParse(
        row['received_at_utc']?.toString() ?? '',
      );
      if (scanTime == null) continue;
      final marker = scansById.putIfAbsent(
        id,
        () => ScanMarker(
          id: id,
          time: scanTime,
          position: points[_nearestStepIndex(stepTimes, scanTime)],
          accessPoints: [],
        ),
      );
      if (row['bssid'] != null) {
        marker.accessPoints.add(Map<String, dynamic>.from(row));
      }
    }
    return SurveyMapData(
      points: points,
      scans: scansById.values.toList(),
      stepCount: stepCount,
    );
  }

  int _nearestStepIndex(List<DateTime> stepTimes, DateTime scanTime) {
    var nearest = 0;
    var bestDifference = double.infinity;
    for (var index = 0; index < stepTimes.length; index++) {
      final difference = stepTimes[index]
          .difference(scanTime)
          .inMilliseconds
          .abs()
          .toDouble();
      if (difference < bestDifference) {
        bestDifference = difference;
        nearest = index;
      }
    }
    return nearest;
  }
}
