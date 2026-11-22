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

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HealthSnapshot> _load() async {
    final sessions = await widget.database.getSessions(limit: 365);
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

  @override
  Widget build(BuildContext context) => FutureBuilder<_HealthSnapshot>(
    future: _future,
    builder: (context, snapshot) {
      final data = snapshot.data;
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
            _CoverageCard(data: data),
            const SizedBox(height: 12),
            for (final entry in data.samples.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MetricCard(type: entry.key, samples: entry.value),
              ),
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
  const _CoverageCard({required this.data});
  final _HealthSnapshot data;

  @override
  Widget build(BuildContext context) {
    final total = data.samples.values.fold<int>(0, (sum, values) => sum + values.length);
    final first = data.samples.values.expand((values) => values).map((s) => s.measuredAt).reduce((a, b) => a.isBefore(b) ? a : b);
    final last = data.samples.values.expand((values) => values).map((s) => s.measuredAt).reduce((a, b) => a.isAfter(b) ? a : b);
    return SectionCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Доступные данные', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text('$total измерений · ${data.samples.length} типа показателей'),
        const SizedBox(height: 4),
        Text('${_date(first)} — ${_date(last)}', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
      ],
    ));
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.type, required this.samples});
  final String type;
  final List<_MetricSample> samples;

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
      ],
    ));
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
