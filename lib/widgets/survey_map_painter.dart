import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/survey_map_data.dart';

class SurveyMapPainter extends CustomPainter {
  const SurveyMapPainter(this.points, this.scans, this.selectedScan);

  final List<Offset> points;
  final List<ScanMarker> scans;
  final int? selectedScan;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final all = [...points, ...scans.map((scan) => scan.position)];
    final minX = all.map((point) => point.dx).reduce(math.min);
    final maxX = all.map((point) => point.dx).reduce(math.max);
    final minY = all.map((point) => point.dy).reduce(math.min);
    final maxY = all.map((point) => point.dy).reduce(math.max);
    final spanX = math.max(1.0, (maxX - minX).abs()).toDouble();
    final spanY = math.max(1.0, (maxY - minY).abs()).toDouble();
    const padding = 30.0;
    final scale = math
        .max(
          0.1,
          math.min(
            (size.width - 2 * padding) / spanX,
            (size.height - 2 * padding) / spanY,
          ),
        )
        .toDouble();
    Offset transform(Offset point) => Offset(
      padding + (point.dx - minX) * scale,
      size.height - padding - (point.dy - minY) * scale,
    );
    final path = Path()
      ..moveTo(transform(points.first).dx, transform(points.first).dy);
    for (final point in points.skip(1)) {
      final transformed = transform(point);
      path.lineTo(transformed.dx, transformed.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.blue
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(
      transform(points.first),
      6,
      Paint()..color = Colors.green,
    );
    canvas.drawRect(
      Rect.fromCenter(center: transform(points.last), width: 10, height: 10),
      Paint()..color = Colors.red,
    );
    for (final scan in scans) {
      final position = transform(scan.position);
      final strongest = scan.accessPoints
          .map((ap) => (ap['rssi'] as num?)?.toInt() ?? -100)
          .fold<int>(-100, math.max);
      final radiusMeters = math.max(
        1.0,
        math.min(8.0, math.pow(10, (-strongest - 35) / 30).toDouble()),
      );
      final radius = math.max(5.0, radiusMeters * scale);
      canvas.drawCircle(
        position,
        radius,
        Paint()
          ..color = Colors.orange.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        position,
        radius,
        Paint()
          ..color = Colors.orange.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      canvas.drawCircle(
        position,
        selectedScan == scan.id ? 7 : 5,
        Paint()
          ..color = selectedScan == scan.id ? Colors.deepOrange : Colors.orange,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SurveyMapPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.scans != scans ||
      oldDelegate.selectedScan != selectedScan;
}
