import 'package:flutter/material.dart';
import '../../data/sleep_database.dart';
import '../../models/sleep_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import '../../widgets/screen_header.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key, required this.database});
  final SleepDatabase database;

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  late Future<_HealthSnapshot> _future;
  int _days = 30;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HealthSnapshot> _load() async {
    final sessions = await widget.database.getSessions(limit: 5000);
    final samples = <String, List<_MetricSample>>{};
    for (final session in sessions) {
      final rows = await widget.database.getMetrics(session.id);
      for (final row in rows) {
        final type = row['metric_type'] as String? ?? 'unknown';
        final value = row['value'];
        final measuredAt = DateTime.tryParse(row['measured_at'] as String? ?? '');
        if (value is! num || measuredAt == null || !value.isFinite) continue;
        samples.putIfAbsent(type, () => []).add(_MetricSample(
          value: value.toDouble(),
          unit: row['unit'] as String? ?? '',
          measuredAt: measuredAt,
          source: row['source'] as String? ?? 'Источник не указан',
          sessionId: session.id,
        ));
      }
    }
    for (final values in samples.values) {
      values.sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    }
    return _HealthSnapshot(sessions: sessions, samples: samples);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _chooseRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _customRange ?? DateTimeRange(start: now.subtract(const Duration(days: 29)), end: now),
      helpText: 'Выберите период анализа',
      saveText: 'Применить',
    );
    if (picked != null && mounted) setState(() => _customRange = picked);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_HealthSnapshot>(
    future: _future,
    builder: (context, snapshot) {
      final data = snapshot.data;
      final now = DateTime.now();
      final selectedStart = _customRange?.start ?? DateTime(now.year, now.month, now.day).subtract(Duration(days: _days - 1));
      final selectedEnd = _customRange == null ? now : DateTime(_customRange!.end.year, _customRange!.end.month, _customRange!.end.day, 23, 59, 59);
      final durationDays = selectedEnd.difference(selectedStart).inDays + 1;
      final previousStart = selectedStart.subtract(Duration(days: durationDays));
      final previousEnd = selectedStart.subtract(const Duration(microseconds: 1));
      final visible = <String, List<_MetricSample>>{};
      final previous = <String, List<_MetricSample>>{};
      if (data != null) {
        for (final entry in data.samples.entries) {
          final currentPoints = entry.value.where((sample) => !sample.measuredAt.isBefore(selectedStart) && !sample.measuredAt.isAfter(selectedEnd)).toList();
          final previousPoints = entry.value.where((sample) => !sample.measuredAt.isBefore(previousStart) && !sample.measuredAt.isAfter(previousEnd)).toList();
          if (currentPoints.isNotEmpty) visible[entry.key] = currentPoints;
          if (previousPoints.isNotEmpty) previous[entry.key] = previousPoints;
        }
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        children: [
          const ScreenHeader(
            title: 'Моё здоровье',
            subtitle: 'Физиологические измерения из разрешённых источников',
            icon: Icons.favorite_rounded,
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text(
              data == null ? 'Загрузка данных…' : 'Ночных записей в истории: ${data.sessions.length}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            )),
            IconButton(
              tooltip: 'Обновить',
              onPressed: snapshot.connectionState == ConnectionState.waiting ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ]),
          if (snapshot.connectionState == ConnectionState.waiting)
            const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
          else if (snapshot.hasError)
            SectionCard(child: Text('Не удалось загрузить показатели: ${snapshot.error}'))
          else if (data == null || data.samples.isEmpty)
            const SectionCard(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Пока нет физиологических измерений', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 8),
                Text('Здесь появятся только реальные показатели, полученные из Apple Health. Отсутствующие значения не заменяются расчётными или условными данными.',
                  style: TextStyle(color: AppTheme.muted, height: 1.45)),
              ],
            ))
          else ...[
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 дней')),
                ButtonSegment(value: 30, label: Text('30 дней')),
                ButtonSegment(value: 90, label: Text('90 дней')),
                ButtonSegment(value: 365, label: Text('Год')),
              ],
              selected: {_days},
              onSelectionChanged: (value) => setState(() { _days = value.first; _customRange = null; }),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: _chooseRange,
                icon: const Icon(Icons.date_range_rounded),
                label: Text(_customRange == null ? 'Произвольный период' : '${_date(_customRange!.start)} — ${_date(_customRange!.end)}'),
              )),
              if (_customRange != null) IconButton(tooltip: 'Сбросить период', onPressed: () => setState(() => _customRange = null), icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              const SectionCard(child: Text('За выбранный период измерений нет. Отсутствие записей не означает нулевые значения.', style: TextStyle(color: AppTheme.muted)))
            else ...[
              _CoverageCard(samples: visible),
              const SizedBox(height: 12),
              _ComparisonCard(current: visible, previous: previous, previousStart: previousStart, previousEnd: previousEnd),
              const SizedBox(height: 12),
              for (final entry in visible.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _MetricCard(type: entry.key, samples: entry.value, sessions: {for (final session in data.sessions) session.id: session}),
                ),
            ],
            const Text(
              'Показатели отражают данные, переданные источником. Они не являются медицинским заключением. Наличие пропусков зависит от устройства, разрешений и фактических измерений.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45),
            ),
          ],
        ],
      );
    },
  );
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.current, required this.previous, required this.previousStart, required this.previousEnd});
  final Map<String, List<_MetricSample>> current;
  final Map<String, List<_MetricSample>> previous;
  final DateTime previousStart;
  final DateTime previousEnd;

  @override
  Widget build(BuildContext context) {
    final common = current.keys.where((key) => previous.containsKey(key)).toList();
    if (common.isEmpty) {
      return const SectionCard(child: Text('Для сравнения пока недостаточно измерений в предыдущем равном по длительности периоде.', style: TextStyle(color: AppTheme.muted)));
    }
    return SectionCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Сравнение с предыдущим периодом', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('${_date(previousStart)} — ${_date(previousEnd)}', style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
        const SizedBox(height: 10),
        for (final key in common) ...[
          _ComparisonRow(type: key, current: current[key]!, previous: previous[key]!),
          if (key != common.last) const Divider(height: 18),
        ],
        const SizedBox(height: 6),
        const Text('Сравниваются средние значения доступных измерений. Разница сама по себе не является медицинской оценкой.', style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35)),
      ],
    ));
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.type, required this.current, required this.previous});
  final String type;
  final List<_MetricSample> current;
  final List<_MetricSample> previous;

  double _average(List<_MetricSample> values) => values.fold<double>(0, (sum, item) => sum + item.value) / values.length;

  @override
  Widget build(BuildContext context) {
    final currentAverage = _average(current);
    final previousAverage = _average(previous);
    final delta = currentAverage - previousAverage;
    final unit = current.last.unit;
    final percent = previousAverage == 0 ? null : delta / previousAverage * 100;
    final deltaText = (delta > 0 ? '+' : '') + _number(delta) + ' ' + unit;
    final percentText = percent == null ? '' : ' (' + (percent > 0 ? '+' : '') + _number(percent) + '%)';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(type, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text('Сейчас: ${_number(currentAverage)} $unit · ранее: ${_number(previousAverage)} $unit', style: const TextStyle(fontSize: 12)),
      Text('Изменение: $deltaText$percentText', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
      Text('${current.length} / ${previous.length} измерений', style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
    ]);
  }
}

class _HealthSnapshot {
  const _HealthSnapshot({required this.sessions, required this.samples});
  final List<SleepSession> sessions;
  final Map<String, List<_MetricSample>> samples;
}

class _MetricSample {
  const _MetricSample({required this.value, required this.unit, required this.measuredAt, required this.source, required this.sessionId});
  final double value;
  final String unit;
  final DateTime measuredAt;
  final String source;
  final String sessionId;
}

class _CoverageCard extends StatelessWidget {
  const _CoverageCard({required this.samples});
  final Map<String, List<_MetricSample>> samples;

  @override
  Widget build(BuildContext context) {
    final all = samples.values.expand((values) => values).toList();
    final total = all.length;
    final first = all.map((s) => s.measuredAt).reduce((a, b) => a.isBefore(b) ? a : b);
    final last = all.map((s) => s.measuredAt).reduce((a, b) => a.isAfter(b) ? a : b);
    return SectionCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Доступные данные', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text('$total измерений · ${samples.length} типа показателей'),
        const SizedBox(height: 4),
        Text('${_date(first)} — ${_date(last)}', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
      ],
    ));
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.type, required this.samples, required this.sessions});
  final String type;
  final List<_MetricSample> samples;
  final Map<String, SleepSession> sessions;

  String get title => switch (type) {
    'Пульс' => 'Пульс',
    'Частота дыхания' => 'Частота дыхания',
    'Насыщение кислородом' => 'SpO₂',
    'Вариабельность пульса SDNN' => 'Вариабельность сердечного ритма (SDNN)',
    'Температура запястья' => 'Температура запястья',
    _ => type,
  };

  @override
  Widget build(BuildContext context) {
    final values = samples.map((s) => s.value).toList();
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final average = values.reduce((a, b) => a + b) / values.length;
    final latest = samples.last;
    final unit = latest.unit;
    return SectionCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_number(latest.value)} $unit', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const Text('Последнее измерение', style: TextStyle(color: AppTheme.muted, fontSize: 11)),
          ])),
          Text('${samples.length} точек', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        SizedBox(height: 54, width: double.infinity, child: CustomPaint(
          painter: _SparklinePainter(values),
        )),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _Stat(label: 'Минимум', value: '${_number(min)} $unit')),
          Expanded(child: _Stat(label: 'Среднее', value: '${_number(average)} $unit')),
          Expanded(child: _Stat(label: 'Максимум', value: '${_number(max)} $unit')),
        ]),
        const SizedBox(height: 8),
        Text('Последнее: ${_date(latest.measuredAt)} · ${latest.source}',
          style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
        Align(alignment: Alignment.centerRight, child: TextButton.icon(
          onPressed: () => _showHistory(context),
          icon: const Icon(Icons.history_rounded, size: 17),
          label: const Text('История измерений'),
        )),
      ],
    ));
  }

  void _showHistory(BuildContext context) {
    final rows = [...samples]..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('История: ' + title),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 12),
            itemBuilder: (context, index) {
              final sample = rows[index];
              final session = sessions[sample.sessionId];
              final nightLabel = session == null ? 'Ночная запись не найдена' : 'Ночь от ' + _date(session.startedAt);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_number(sample.value) + ' ' + sample.unit, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(_date(sample.measuredAt) + ' · ' + nightLabel, style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
                  Text(sample.source, style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                ],
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Закрыть'))],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      const SizedBox(height: 3),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
    ],
  );
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values);
  final List<double> values;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final range = max - min;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * size.width / (values.length - 1);
      final normalized = range == 0 ? .5 : (values[i] - min) / range;
      final y = size.height - normalized * (size.height - 8) - 4;
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    final paint = Paint()
      ..color = const Color(0xFFB9A7FF)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => oldDelegate.values != values;
}

String _number(double value) => value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
