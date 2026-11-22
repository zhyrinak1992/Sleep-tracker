import 'dart:math' as math;
import 'package:flutter/material.dart';

class ClimateTrendPoint {
  const ClimateTrendPoint(this.measuredAt, this.value);
  final DateTime measuredAt;
  final double value;
}

List<List<ClimateTrendPoint>> climateTrendSegments(
  Iterable<Map<String, Object?>> samples, {
  required String metricType,
  Duration maxGap = const Duration(minutes: 45),
}) {
  final points = <ClimateTrendPoint>[];
  for (final row in samples) {
    if (row['metric_type'] != metricType || row['value'] is! num || row['measured_at'] is! String) continue;
    final value = (row['value'] as num).toDouble();
    final measuredAt = DateTime.tryParse(row['measured_at']! as String);
    if (!value.isFinite || measuredAt == null) continue;
    points.add(ClimateTrendPoint(measuredAt.toLocal(), value));
  }
  points.sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
  final segments = <List<ClimateTrendPoint>>[];
  for (final point in points) {
    if (segments.isEmpty ||
        point.measuredAt.difference(segments.last.last.measuredAt) > maxGap) {
      segments.add(<ClimateTrendPoint>[point]);
    } else {
      segments.last.add(point);
    }
  }
  return segments;
}

/// График реальных показаний датчика. Большие пропуски не соединяются линией.
class ClimateTrendChart extends StatelessWidget {
  const ClimateTrendChart({
    super.key,
    required this.samples,
    required this.metricType,
    required this.unit,
  });

  final List<Map<String, Object?>> samples;
  final String metricType;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final segments = climateTrendSegments(samples, metricType: metricType);
    final points = segments.expand((segment) => segment).toList();
    if (points.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Нет измерений для графика', style: TextStyle(color: Colors.grey, fontSize: 11)),
      );
    }
    final minimum = points.map((point) => point.value).reduce(math.min);
    final maximum = points.map((point) => point.value).reduce(math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 112,
          width: double.infinity,
          child: CustomPaint(
            painter: _ClimateTrendPainter(
              segments: segments,
              minimum: minimum,
              maximum: maximum,
              lineColor: Theme.of(context).colorScheme.primary,
              gridColor: Theme.of(context).dividerColor,
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${minimum.toStringAsFixed(1)} $unit', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            Text('${points.length} измерений', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            Text('${maximum.toStringAsFixed(1)} $unit', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_date(points.first.measuredAt), style: const TextStyle(fontSize: 10, color: Colors.grey)),
            Text(_date(points.last.measuredAt), style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ],
    );
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}';
}

class _ClimateTrendPainter extends CustomPainter {
  const _ClimateTrendPainter({
    required this.segments,
    required this.minimum,
    required this.maximum,
    required this.lineColor,
    required this.gridColor,
  });

  final List<List<ClimateTrendPoint>> segments;
  final double minimum;
  final double maximum;
  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 5.0;
    final plot = Rect.fromLTRB(inset, inset, size.width - inset, size.height - inset);
    final grid = Paint()
      ..color = gridColor.withOpacity(0.35)
      ..strokeWidth = 0.7;
    for (var i = 0; i < 4; i++) {
      final y = plot.top + plot.height * i / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }
    final allPoints = segments.expand((segment) => segment).toList();
    final first = allPoints.first.measuredAt;
    final last = allPoints.last.measuredAt;
    final span = last.difference(first).inMilliseconds;
    final range = maximum - minimum;
    final padding = range == 0 ? math.max(maximum.abs() * 0.05, 0.5) : range * 0.08;
    final low = minimum - padding;
    final high = maximum + padding;
    Offset position(ClimateTrendPoint point) {
      final x = span <= 0 ? plot.center.dx : plot.left + point.measuredAt.difference(first).inMilliseconds / span * plot.width;
      final y = plot.bottom - (point.value - low) / (high - low) * plot.height;
      return Offset(x, y);
    }
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dot = Paint()..color = lineColor;
    for (final segment in segments) {
      if (segment.length > 1) {
        final start = position(segment.first);
        final path = Path()..moveTo(start.dx, start.dy);
        for (final point in segment.skip(1)) {
          final offset = position(point);
          path.lineTo(offset.dx, offset.dy);
        }
        canvas.drawPath(path, line);
      }
      for (final point in segment) {
        canvas.drawCircle(position(point), 2.5, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ClimateTrendPainter oldDelegate) =>
      oldDelegate.segments != segments ||
      oldDelegate.minimum != minimum ||
      oldDelegate.maximum != maximum ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.gridColor != gridColor;
}
