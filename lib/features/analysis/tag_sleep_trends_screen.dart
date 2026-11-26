import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../models/sleep_tag.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import '../diary/sleep_session_metrics.dart';
import 'tag_sleep_comparison.dart';
import 'tag_sleep_trend_analysis.dart';

class TagSleepTrendsScreen extends StatefulWidget {
  const TagSleepTrendsScreen({
    super.key,
    required this.database,
  });

  final SleepDatabase database;

  @override
  State<TagSleepTrendsScreen> createState() => _TagSleepTrendsScreenState();
}

class _TagSleepTrendsData {
  const _TagSleepTrendsData({
    required this.sessions,
    required this.tagsBySession,
    required this.customTags,
    required this.awakeningCounts,
    required this.efficiency,
    required this.latency,
  });

  final List<SleepSession> sessions;
  final Map<String, Set<String>> tagsBySession;
  final List<SleepTag> customTags;
  final Map<String, int> awakeningCounts;
  final Map<String, double> efficiency;
  final Map<String, int> latency;
}

class _TagSleepTrendsScreenState extends State<TagSleepTrendsScreen> {
  late Future<_TagSleepTrendsData> _future;
  TagSleepMetric _metric = TagSleepMetric.sleepDuration;
  Set<String> _selected = {'caffeine', 'stress', 'activity'};

  static const _lineColors = <Color>[
    AppTheme.teal,
    Color(0xFF9B8CFF),
    Color(0xFFFFB86B),
    Color(0xFFFF8FA3),
    Color(0xFF72C8E8),
  ];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_TagSleepTrendsData> _load() async {
    final sessions = await widget.database.getSessions(limit: null);
    final ids = sessions.map((session) => session.id).toList();
    final tags = await widget.database.getTagsForSessions(ids);
    final stages = await widget.database.getStagesForSessions(ids);
    final awakeningCounts = <String, int>{};
    final efficiency = <String, double>{};
    final latency = <String, int>{};
    for (final session in sessions) {
      final metrics = SleepSessionMetrics.calculate(
        session: session,
        stages: stages[session.id] ?? const <Map<String, Object?>>[],
      );
      if (metrics.hasAwakeSamples &&
          metrics.stageCoveragePercent != null &&
          metrics.stageCoveragePercent! >= 80) {
        awakeningCounts[session.id] = metrics.awakeningCount;
      }
      if (metrics.sleepEfficiencyPercent != null) {
        efficiency[session.id] = metrics.sleepEfficiencyPercent!;
      }
      if (metrics.sleepLatencyMinutes != null) {
        latency[session.id] = metrics.sleepLatencyMinutes!;
      }
    }
    final customTags = await CustomSleepTagStore(
      widget.database.getAppMetadata,
      widget.database.setAppMetadata,
    ).load();
    return _TagSleepTrendsData(
      sessions: sessions,
      tagsBySession: tags,
      customTags: customTags,
      awakeningCounts: awakeningCounts,
      efficiency: efficiency,
      latency: latency,
    );
  }

  String _formatValue(double? value) {
    if (value == null) return 'Нет данных';
    switch (_metric) {
      case TagSleepMetric.sleepDuration:
        final minutes = value.round();
        return '${minutes ~/ 60} ч ${minutes % 60} мин';
      case TagSleepMetric.sleepEfficiency:
        return '${value.toStringAsFixed(1)}%';
      case TagSleepMetric.sleepLatency:
        return '${value.round()} мин';
      case TagSleepMetric.morningRating:
        return '${value.toStringAsFixed(1)} из 5';
      case TagSleepMetric.awakeningCount:
        return '${value.toStringAsFixed(1)} эпизода';
    }
  }

  String _formatDifference(double? value) {
    if (value == null) return 'Недостаточно данных';
    final sign = value > 0 ? '+' : value < 0 ? '−' : '';
    final absolute = value.abs();
    switch (_metric) {
      case TagSleepMetric.sleepDuration:
        final minutes = absolute.round();
        return '$sign${minutes ~/ 60} ч ${minutes % 60} мин';
      case TagSleepMetric.sleepEfficiency:
        return '$sign${absolute.toStringAsFixed(1)} п. п.';
      case TagSleepMetric.sleepLatency:
        return '$sign${absolute.round()} мин';
      case TagSleepMetric.morningRating:
        return '$sign${absolute.toStringAsFixed(1)} балла';
      case TagSleepMetric.awakeningCount:
        return '$sign${absolute.toStringAsFixed(1)} эпизода';
    }
  }

  Future<void> _showPointDetails(
    TagSleepTrendSeries series,
    TagSleepTrendPoint point,
    Map<String, SleepSession> sessionsById,
    String tagLabel,
  ) async {
    final result = point.comparison;
    Widget group(String title, TagSleepGroupSummary summary) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Среднее: ${_formatValue(summary.average)}'),
          Text('Наблюдений: ${summary.nights}'),
          if (summary.sessionIds.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...List.generate(summary.sessionIds.length, (index) {
              final session = sessionsById[summary.sessionIds[index]];
              final value = index < summary.values.length ? summary.values[index] : null;
              if (session == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${DateFormat('d MMM yyyy', 'ru').format(session.startedAt)} · ${_formatValue(value)}',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              );
            }),
          ],
        ],
      );
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${DateFormat('LLLL yyyy', 'ru').format(point.month)} · $tagLabel'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              group('С отметкой', result.withTag),
              const Divider(height: 22),
              group('Без отметки', result.withoutTag),
              const SizedBox(height: 12),
              Text(
                result.isSufficient
                    ? 'Разница средних: ${_formatDifference(result.difference)}'
                    : 'Для сравнения нужны минимум ${TagSleepComparison.minimumNightsPerGroup} ночей в каждой группе.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Это описательное сопоставление. Оно не доказывает, что отметка стала причиной изменения сна.',
                style: TextStyle(color: AppTheme.muted, fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Динамика закономерностей'),
      actions: [IconButton(
        tooltip: 'Обновить данные',
        onPressed: () => setState(() => _future = _load()),
        icon: const Icon(Icons.refresh_rounded),
      )],
    ),
    body: FutureBuilder<_TagSleepTrendsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Не удалось загрузить историю отметок: ${snapshot.error}'),
          ));
        }
        final data = snapshot.data!;
        final availableTags = [...SleepTag.catalog, ...data.customTags];
        final tags = data.sessions.where((session) =>
          session.endedAt != null && session.endedAt!.isAfter(session.startedAt) && session.deletedAt == null).toList();
        if (tags.isEmpty) {
          return const Center(child: Text('Пока нет завершённых ночей для анализа.'));
        }
        final availableKeys = availableTags.map((tag) => tag.key).toSet();
        final selected = _selected.where(availableKeys.contains).toSet();
        if (selected.isEmpty) {
          selected.addAll(availableTags.take(3).map((tag) => tag.key));
        }
        final orderedTags = availableTags.where((tag) => selected.contains(tag.key)).take(5).toList();
        final first = tags.map((session) => session.startedAt).reduce((a, b) => a.isBefore(b) ? a : b);
        final last = tags.map((session) => session.startedAt).reduce((a, b) => a.isAfter(b) ? a : b);
        final startMonth = DateTime(first.year, first.month);
        final endMonth = DateTime(last.year, last.month + 1);
        final series = TagSleepTrendAnalysis.calculate(
          sessions: data.sessions,
          tagsBySession: data.tagsBySession,
          tagKeys: orderedTags.map((tag) => tag.key),
          startMonth: startMonth,
          endMonthExclusive: endMonth,
          metric: _metric,
          awakeningCountsBySession: data.awakeningCounts,
          efficiencyBySession: data.efficiency,
          sleepLatencyBySession: data.latency,
        );
        final months = TagSleepTrendAnalysis.monthsBetween(startMonth, endMonth);
        final sessionsById = {for (final session in data.sessions) session.id: session};
        final chartWidth = math.max(340.0, months.length * 62.0).toDouble();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            const SectionCard(child: Text(
              'Каждая линия — отдельная отметка. Для каждого месяца сравниваются завершённые ночи с этой отметкой и без неё. Ночи могут независимо участвовать в нескольких линиях.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45),
            )),
            const SizedBox(height: 12),
            SectionCard(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Показатель', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<TagSleepMetric>(
                  value: _metric,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: TagSleepMetric.values.map((metric) => DropdownMenuItem(
                    value: metric,
                    child: Text(metric.label),
                  )).toList(),
                  onChanged: (value) => setState(() {
                    if (value != null) _metric = value;
                  }),
                ),
                const SizedBox(height: 14),
                const Text('Отметки на графике · до 5 линий', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: availableTags.map((tag) => FilterChip(
                    label: Text(tag.label),
                    selected: selected.contains(tag.key),
                    onSelected: (value) {
                      setState(() {
                        if (value && _selected.length < 5) {
                          _selected.add(tag.key);
                        } else if (!value) {
                          _selected.remove(tag.key);
                        }
                      });
                    },
                  )).toList(),
                ),
              ],
            )),
            const SizedBox(height: 12),
            SectionCard(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Разница средних по месяцам', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  '${_metric.label}: с отметкой минус без отметки · минимум ${TagSleepComparison.minimumNightsPerGroup} ночи в каждой группе',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: chartWidth,
                    height: 244,
                    child: _TagTrendChart(
                      series: series,
                      months: months,
                      colors: _lineColors,
                      onTapPoint: (monthIndex, seriesIndex) {
                        if (monthIndex < 0 || monthIndex >= months.length) return;
                        if (seriesIndex < 0 || seriesIndex >= series.length) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('В этом месяце пока недостаточно данных для сравнения.')),
                          );
                          return;
                        }
                        final selectedSeries = series[seriesIndex];
                        final tagLabel = availableTags.firstWhere((tag) => tag.key == selectedSeries.tagKey).label;
                        _showPointDetails(selectedSeries, selectedSeries.points[monthIndex], sessionsById, tagLabel);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: List.generate(series.length, (index) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 18, height: 3, color: _lineColors[index % _lineColors.length]),
                      const SizedBox(width: 5),
                      Text(
                        availableTags.firstWhere((tag) => tag.key == series[index].tagKey).label,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  )),
                ),
              ],
            )),
            const SizedBox(height: 12),
            SectionCard(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Наблюдения по месяцам', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ...months.asMap().entries.toList().reversed.map((entry) {
                  final month = entry.value;
                  final index = entry.key;
                  return ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(DateFormat('LLLL yyyy', 'ru').format(month)),
                    subtitle: Text(series.map((item) {
                      final point = item.points[index];
                      return '${availableTags.firstWhere((tag) => tag.key == item.tagKey).label}: ${point.comparison.withTag.nights}/${point.comparison.withoutTag.nights}';
                    }).join(' · ')),
                    children: series.map((item) {
                      final point = item.points[index];
                      final label = availableTags.firstWhere((tag) => tag.key == item.tagKey).label;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.only(left: 8),
                        title: Text(label),
                        subtitle: Text(
                          point.comparison.isSufficient
                              ? 'Разница: ${_formatDifference(point.comparison.difference)}'
                              : 'Недостаточно данных · ${point.comparison.withTag.nights}/${point.comparison.withoutTag.nights} ночей',
                        ),
                        onTap: () => _showPointDetails(item, point, sessionsById, label),
                      );
                    }).toList(),
                  );
                }),
              ],
            )),
          ],
        );
      },
    ),
  );
}

class _TagTrendChart extends StatelessWidget {
  const _TagTrendChart({
    required this.series,
    required this.months,
    required this.colors,
    required this.onTapPoint,
  });

  final List<TagSleepTrendSeries> series;
  final List<DateTime> months;
  final List<Color> colors;
  final void Function(int monthIndex, int seriesIndex) onTapPoint;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapUp: (details) {
      const left = 42.0;
      final totalWidth = math.max(340.0, months.length * 62.0).toDouble();
      final plotWidth = math.max(1.0, totalWidth - left - 12).toDouble();
      final dx = (details.localPosition.dx - left).clamp(0.0, plotWidth);
      final monthIndex = months.length <= 1 ? 0 : (dx / plotWidth * (months.length - 1)).round();
      final values = series.expand((line) => line.points)
          .where((point) => point.comparison.difference != null)
          .map((point) => point.comparison.difference!.abs()).toList();
      final maxValue = values.isEmpty ? 1.0 : math.max(1.0, values.reduce((a, b) => math.max(a, b).toDouble())).toDouble();
      const top = 14.0;
      const plotHeight = 244.0 - 14.0 - 38.0;
      var nearestSeries = -1;
      var nearestDistance = double.infinity;
      for (var seriesIndex = 0; seriesIndex < series.length; seriesIndex++) {
        final comparison = series[seriesIndex].points[monthIndex].comparison;
        final value = comparison.isSufficient ? comparison.difference : null;
        if (value == null) continue;
        final y = top + plotHeight * (maxValue - value) / (2 * maxValue);
        final distance = (details.localPosition.dy - y).abs();
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearestSeries = seriesIndex;
        }
      }
      onTapPoint(monthIndex, nearestSeries);
    },
    child: CustomPaint(
      painter: _TagTrendPainter(series: series, months: months, colors: colors),
      child: const SizedBox.expand(),
    ),
  );
}

class _TagTrendPainter extends CustomPainter {
  const _TagTrendPainter({
    required this.series,
    required this.months,
    required this.colors,
  });

  final List<TagSleepTrendSeries> series;
  final List<DateTime> months;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty) return;
    const left = 42.0;
    const right = 12.0;
    const top = 14.0;
    const bottom = 38.0;
    final plotWidth = math.max(1.0, size.width - left - right).toDouble();
    final plotHeight = math.max(1.0, size.height - top - bottom).toDouble();
    final values = series.expand((line) => line.points)
      .where((point) => point.comparison.difference != null)
      .map((point) => point.comparison.difference!.abs()).toList();
    final maxValue = values.isEmpty ? 1.0 : math.max(1.0, values.reduce((a, b) => math.max(a, b).toDouble())).toDouble();
    final textStyle = const TextStyle(color: AppTheme.muted, fontSize: 9);
    void drawLabel(String text, Offset offset, {double width = 38}) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: width);
      painter.paint(canvas, offset);
    }

    final gridPaint = Paint()
      ..color = AppTheme.surfaceLight
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final fraction = i / 4;
      final y = top + plotHeight * fraction;
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), gridPaint);
      final value = maxValue - maxValue * 2 * fraction;
      drawLabel(value.toStringAsFixed(0), Offset(0, y - 6), width: left - 4);
    }
    final zeroY = top + plotHeight / 2;
    canvas.drawLine(
      Offset(left, zeroY),
      Offset(size.width - right, zeroY),
      Paint()..color = AppTheme.muted.withValues(alpha: 0.65)..strokeWidth = 1.2,
    );

    for (var lineIndex = 0; lineIndex < series.length; lineIndex++) {
      final line = series[lineIndex];
      final color = colors[lineIndex % colors.length];
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      Path? path;
      var hasPoint = false;
      for (var i = 0; i < line.points.length; i++) {
        final value = line.points[i].comparison.difference;
        if (value == null) {
          if (path != null) canvas.drawPath(path, paint);
          path = null;
          hasPoint = false;
          continue;
        }
        final x = months.length <= 1
            ? left + plotWidth / 2
            : left + plotWidth * i / (months.length - 1);
        final y = top + plotHeight * (maxValue - value) / (2 * maxValue);
        final point = Offset(x, y);
        if (path == null) {
          path = Path()..moveTo(x, y);
          hasPoint = true;
        } else if (hasPoint) {
          path.lineTo(x, y);
        }
        canvas.drawCircle(point, 4, Paint()..color = color);
      }
      if (path != null) canvas.drawPath(path, paint);
    }

    for (var i = 0; i < months.length; i++) {
      final x = months.length <= 1
          ? left + plotWidth / 2
          : left + plotWidth * i / (months.length - 1);
      final label = DateFormat('MMM yy', 'ru').format(months[i]);
      drawLabel(label, Offset(x - 23, size.height - 24), width: 48);
    }
  }

  @override
  bool shouldRepaint(covariant _TagTrendPainter oldDelegate) =>
      oldDelegate.series != series ||
      oldDelegate.months != months ||
      oldDelegate.colors != colors;
}
