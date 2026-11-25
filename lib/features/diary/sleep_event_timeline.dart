import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

enum SleepTimelineEventKind { awakening, audio, pulse }

class SleepTimelineEvent {
  const SleepTimelineEvent({
    required this.kind,
    required this.at,
    required this.title,
    required this.detail,
    this.until,
    this.source,
    this.isElevated = false,
  });

  final SleepTimelineEventKind kind;
  final DateTime at;
  final DateTime? until;
  final String title;
  final String detail;
  final String? source;
  final bool isElevated;
}

class SleepEventTimeline {
  SleepEventTimeline._();

  static List<SleepTimelineEvent> build({
    required List<Map<String, Object?>> stages,
    required List<Map<String, Object?>> metrics,
    required List<Map<String, Object?>> audioEvents,
  }) {
    final events = <SleepTimelineEvent>[];

    final awakeIntervals = <({DateTime start, DateTime end})>[];
    for (final row in stages) {
      final stage = (row['stage'] as String? ?? '').trim().toLowerCase();
      if (!(stage == 'awake' || stage == 'бодрствование' ||
          stage.contains('awake') || stage.contains('бодр'))) {
        continue;
      }
      final start = _date(row['started_at']);
      final end = _date(row['ended_at']);
      if (start == null || end == null || !end.isAfter(start)) continue;
      awakeIntervals.add((start: start, end: end));
    }
    awakeIntervals.sort((a, b) => a.start.compareTo(b.start));
    if (awakeIntervals.isNotEmpty) {
      var start = awakeIntervals.first.start;
      var end = awakeIntervals.first.end;
      for (final interval in awakeIntervals.skip(1)) {
        if (!interval.start.isAfter(end)) {
          if (interval.end.isAfter(end)) end = interval.end;
        } else {
          _addAwakening(events, start, end);
          start = interval.start;
          end = interval.end;
        }
      }
      _addAwakening(events, start, end);
    }

    final pulseRows = <({DateTime at, double value, String unit, String source})>[];
    for (final row in metrics) {
      if (row['metric_type'] != 'Пульс' || row['value'] is! num) continue;
      final at = _date(row['measured_at']);
      final value = (row['value'] as num).toDouble();
      if (at == null || !value.isFinite || value <= 0) continue;
      pulseRows.add((
        at: at,
        value: value,
        unit: row['unit'] as String? ?? 'уд/мин',
        source: row['source'] as String? ?? '',
      ));
    }
    pulseRows.sort((a, b) => a.at.compareTo(b.at));
    final elevatedIndexes = _relativeHighPulseIndexes(pulseRows.map((x) => x.value).toList());
    for (var i = 0; i < pulseRows.length; i++) {
      final sample = pulseRows[i];
      final elevated = elevatedIndexes.contains(i);
      events.add(SleepTimelineEvent(
        kind: SleepTimelineEventKind.pulse,
        at: sample.at,
        title: elevated ? 'Пульс · выше диапазона этой ночи' : 'Пульс',
        detail: '${_number(sample.value)} ${sample.unit}',
        source: sample.source,
        isElevated: elevated,
      ));
    }

    for (final row in audioEvents) {
      final at = _date(row['captured_at']);
      if (at == null) continue;
      final category = (row['category'] as String? ?? '').trim();
      final title = category.isEmpty || category == 'unknown'
          ? 'Неопределённый звук'
          : category;
      final duration = row['duration_ms'] is num
          ? (row['duration_ms'] as num).toDouble() / 1000
          : null;
      events.add(SleepTimelineEvent(
        kind: SleepTimelineEventKind.audio,
        at: at,
        title: 'Звуковое событие · $title',
        detail: duration == null || !duration.isFinite
            ? 'Отдельный аудиофрагмент'
            : 'Длительность ${duration.toStringAsFixed(1)} с',
        source: row['file_path'] is String && (row['file_path'] as String).isNotEmpty
            ? 'Аудиофайл сохранён'
            : 'Аудиофайл недоступен или истёк срок хранения',
      ));
    }

    events.sort((a, b) {
      final timeOrder = a.at.compareTo(b.at);
      if (timeOrder != 0) return timeOrder;
      return a.kind.index.compareTo(b.kind.index);
    });
    return List.unmodifiable(events);
  }

  static void _addAwakening(
    List<SleepTimelineEvent> events,
    DateTime start,
    DateTime end,
  ) {
    final minutes = end.difference(start).inMinutes;
    if (minutes <= 0) return;
    events.add(SleepTimelineEvent(
      kind: SleepTimelineEventKind.awakening,
      at: start,
      until: end,
      title: 'Период бодрствования',
      detail: '$minutes мин · ${DateFormat('HH:mm').format(start.toLocal())}–${DateFormat('HH:mm').format(end.toLocal())}',
      source: 'По интервалам фаз, предоставленным источником сна',
    ));
  }

  static Set<int> _relativeHighPulseIndexes(List<double> values) {
    if (values.length < 5) return const {};
    final sorted = [...values]..sort();
    final q1 = _percentile(sorted, .25);
    final q3 = _percentile(sorted, .75);
    final spread = q3 - q1;
    if (!spread.isFinite || spread <= 0) return const {};
    final upperFence = q3 + 1.5 * spread;
    return {
      for (var i = 0; i < values.length; i++)
        if (values[i] > upperFence) i,
    };
  }

  static double _percentile(List<double> sorted, double fraction) {
    final position = (sorted.length - 1) * fraction;
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sorted[lower];
    final weight = position - lower;
    return sorted[lower] * (1 - weight) + sorted[upper] * weight;
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

  static String _number(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
}

class SleepEventTimelineCard extends StatelessWidget {
  const SleepEventTimelineCard({super.key, required this.eventsFuture});
  final Future<List<SleepTimelineEvent>> eventsFuture;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SleepTimelineEvent>>(
    future: eventsFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const SectionCard(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Единая временная шкала', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            LinearProgressIndicator(),
          ],
        ));
      }
      if (snapshot.hasError) {
        return const SectionCard(child: Text('Не удалось собрать временную шкалу этой ночи.'));
      }
      final events = snapshot.data ?? const <SleepTimelineEvent>[];
      final pulse = events.where((event) => event.kind == SleepTimelineEventKind.pulse).toList();
      final elevatedCount = pulse.where((event) => event.isElevated).length;
      return SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Единая временная шкала', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          const Text(
            'Звуковые события, интервалы бодрствования и измерения пульса расположены по времени. Пропущенные события не восстанавливаются.',
            style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
          ),
          if (pulse.length >= 2) ...[
            const SizedBox(height: 14),
            const Text('Пульс в течение ночи', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 6),
            SizedBox(
              height: 76,
              width: double.infinity,
              child: CustomPaint(painter: _PulseTimelinePainter(pulse)),
            ),
            if (elevatedCount > 0)
              Text(
                'Выделено точек выше статистического диапазона этой ночи: $elevatedCount. Это не медицинский порог.',
                style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35),
              ),
          ],
          const SizedBox(height: 12),
          if (events.isEmpty)
            const Text('Для этой ночи пока нет временных отметок звуков, бодрствования или пульса.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12))
          else
            for (final event in events) _TimelineEventRow(event: event),
        ],
      ));
    },
  );
}

class _TimelineEventRow extends StatelessWidget {
  const _TimelineEventRow({required this.event});
  final SleepTimelineEvent event;

  @override
  Widget build(BuildContext context) {
    final icon = switch (event.kind) {
      SleepTimelineEventKind.awakening => Icons.visibility_outlined,
      SleepTimelineEventKind.audio => Icons.graphic_eq_rounded,
      SleepTimelineEventKind.pulse => Icons.favorite_outline_rounded,
    };
    final color = event.isElevated
        ? AppTheme.accentPink
        : event.kind == SleepTimelineEventKind.awakening
            ? AppTheme.teal
            : AppTheme.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 9),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(event.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(event.detail, style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
            if (event.source != null && event.source!.isNotEmpty)
              Text(event.source!, style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
          ],
        )),
        const SizedBox(width: 8),
        Text(DateFormat('HH:mm').format(event.at.toLocal()),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _PulseTimelinePainter extends CustomPainter {
  const _PulseTimelinePainter(this.events);
  final List<SleepTimelineEvent> events;

  @override
  void paint(Canvas canvas, Size size) {
    if (events.length < 2) return;
    final values = events.map((event) => double.tryParse(
      event.detail.split(' ').first.replaceAll(',', '.'),
    ) ?? 0).toList();
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = maxValue - minValue;
    final path = Path();
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = i * size.width / (values.length - 1);
      final normalized = range == 0 ? .5 : (values[i] - minValue) / range;
      final y = size.height - 10 - normalized * (size.height - 20);
      final point = Offset(x, y);
      points.add(point);
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    canvas.drawPath(path, Paint()
      ..color = AppTheme.teal
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], events[i].isElevated ? 4.5 : 3,
        Paint()..color = events[i].isElevated ? AppTheme.accentPink : AppTheme.teal);
    }
  }

  @override
  bool shouldRepaint(covariant _PulseTimelinePainter oldDelegate) =>
      oldDelegate.events != events;
}
