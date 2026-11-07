import 'package:flutter/material.dart';

class SurveyMapData {
  const SurveyMapData({
    required this.points,
    required this.scans,
    required this.stepCount,
  });

  final List<Offset> points;
  final List<ScanMarker> scans;
  final int stepCount;
}

class ScanMarker {
  ScanMarker({
    required this.id,
    required this.time,
    required this.position,
    required this.accessPoints,
  });

  final int id;
  final DateTime time;
  final Offset position;
  final List<Map<String, dynamic>> accessPoints;
}
