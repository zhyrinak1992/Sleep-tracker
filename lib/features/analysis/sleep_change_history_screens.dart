import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/sleep_database.dart';
import '../../data/sleep_change_history.dart';
import '../../theme/app_theme.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/section_card.dart';
import 'sleep_dynamics_screen.dart';


String _formatHistoryDate(Object? value) {
  if (value is! String) return 'Дата не указана';
  final date = DateTime.tryParse(value);
  return date == null ? 'Дата не указана' : DateFormat('d MMM yyyy', 'ru').format(date.toLocal());
}

String _formatPeriod(Object? start, Object? end) {
  if (start is! String || end is! String) return 'Период не указан';
  final a = DateTime.tryParse(start);
  final b = DateTime.tryParse(end);
  if (a == null || b == null) return 'Период не указан';
  final lastDay = DateTime(b.year, b.month, b.day - 1);
  return '${DateFormat('d MMM', 'ru').format(a.toLocal())} — ${DateFormat('d MMM yyyy', 'ru').format(lastDay)}';
}

String _formatHistoryDelta(Map<String, Object?> change) {
  final value = change['delta'];
  final unit = change['unit'] as String? ?? '';
  if (value is! num) return 'Нет числового значения';
  final delta = value.toDouble();
  final sign = delta > 0 ? '+' : '';
  if (unit == 'мин') {
    final minutes = delta.abs().round();
    final magnitude = minutes ~/ 60 == 0
        ? '$minutes мин'
        : minutes % 60 == 0 ? '${minutes ~/ 60} ч' : '${minutes ~/ 60} ч ${minutes % 60} мин';
    return '${delta > 0 ? '+' : delta < 0 ? '−' : ''}$magnitude';
  }
  return '$sign${delta.toStringAsFixed(1)} $unit'.trim();
}

class SleepChangeHistoryScreen extends StatefulWidget {
  const SleepChangeHistoryScreen({super.key, required this.database});
  final SleepDatabase database;

  @override
  State<SleepChangeHistoryScreen> createState() => _SleepChangeHistoryScreenState();
}

class _SleepChangeHistoryScreenState extends State<SleepChangeHistoryScreen> {
  late Future<List<Map<String, Object?>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.database.getSleepChangeHistory();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('История главных изменений')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _future,
      builder: (context, state) {
        if (state.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Не удалось загрузить историю: ${state.error}'),
          ));
        }
        final all = state.data ?? const <Map<String, Object?>>[];
        final latest = SleepChangeHistoryRecords.latestPerMonth(all).reversed.toList();
        if (latest.isEmpty) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('История появится после первого автоматического расчёта в разделе «Моя динамика сна».'),
          ));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            const ScreenHeader(
              title: 'История главных изменений',
              subtitle: 'Сохранённые снимки сравнений и прозрачные версии пересчёта',
              icon: Icons.history_rounded,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SleepChangeHistoryChartScreen(database: widget.database),
              )),
              icon: const Icon(Icons.show_chart_rounded),
              label: const Text('График по месяцам'),
            ),
            const SizedBox(height: 12),
            ...latest.map((snapshot) {
              final key = snapshot['periodKey'];
              final revisions = all.where((item) => item['periodKey'] == key).toList()
                ..sort((a, b) => ((a['version'] as int?) ?? 1).compareTo((b['version'] as int?) ?? 1));
              final change = snapshot['mainChange'];
              final title = change is Map ? change['title'] as String? : null;
              final status = snapshot['mainChangeStatus'];
              final subtitle = title ?? (status == 'insufficient_data'
                  ? 'Недостаточно данных для главного изменения'
                  : 'Одного выраженного главного изменения не выявлено');
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SectionCard(child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${key ?? 'Период'} · v${snapshot['version'] ?? 1}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text('$subtitle\nСформировано: ${_formatHistoryDate(snapshot['generatedAt'])} · версий: ${revisions.length}',
                      style: const TextStyle(fontSize: 12, height: 1.45)),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SleepChangeHistoryDetailScreen(
                      database: widget.database,
                      revisions: revisions,
                    ),
                  )),
                )),
              );
            }),
          ],
        );
      },
    ),
  );
}

class SleepChangeHistoryDetailScreen extends StatelessWidget {
  const SleepChangeHistoryDetailScreen({
    super.key,
    required this.database,
    required this.revisions,
  });

  final SleepDatabase database;
  final List<Map<String, Object?>> revisions;

  @override
  Widget build(BuildContext context) {
    final latest = revisions.isEmpty ? <String, Object?>{} : revisions.last;
    final change = latest['mainChange'] is Map
        ? Map<String, Object?>.from(latest['mainChange'] as Map)
        : null;
    final notable = (latest['notableChanges'] as List? ?? const [])
        .whereType<Map>().map((item) => Map<String, Object?>.from(item)).toList();
    final status = latest['mainChangeStatus'];
    return Scaffold(
      appBar: AppBar(title: const Text('Сохранённый результат')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          ScreenHeader(
            title: '${latest['periodKey'] ?? 'Сравнение'}',
            subtitle: 'Версия ${latest['version'] ?? 1} · сформировано ${_formatHistoryDate(latest['generatedAt'])}',
            icon: Icons.analytics_outlined,
          ),
          const SizedBox(height: 12),
          SectionCard(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Сравниваемые периоды', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Предыдущие 30 дней: ${_formatPeriod(latest['previousStart'], latest['previousEndExclusive'])}'),
              Text('Последние 30 дней: ${_formatPeriod(latest['currentStart'], latest['currentEndExclusive'])}'),
              const Divider(height: 20, color: AppTheme.surfaceLight),
              const Text('Сохранённый персональный итог', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(latest['summary'] as String? ?? 'Итог отсутствует.',
                style: const TextStyle(fontSize: 12, height: 1.5)),
              const SizedBox(height: 12),
              const Text('Главное изменение', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (change != null) ...[
                Text(change['title'] as String? ?? 'Показатель',
                  style: const TextStyle(color: AppTheme.teal, fontWeight: FontWeight.w700)),
                Text(change['description'] as String? ?? ''),
                Text('Разница: ${_formatHistoryDelta(change)} · наблюдений: ${change['previousSamples'] ?? '—'} → ${change['currentSamples'] ?? '—'}',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                Text('Значения: ${change['previousValue']} → ${change['currentValue']} ${change['unit'] ?? ''}',
                  style: const TextStyle(fontSize: 12)),
              ] else
                Text(status == 'insufficient_data'
                    ? 'Главное изменение не формировалось: недостаточно сопоставимых данных.'
                    : 'Выраженного единственного главного изменения не выявлено.',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45)),
            ],
          )),
          if (notable.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Другие заметные изменения', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...notable.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item['title'] as String? ?? 'Показатель',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(item['description'] as String? ?? '',
                      style: const TextStyle(fontSize: 12, height: 1.4)),
                  ]),
                )),
              ],
            )),
          ],
          if (revisions.length > 1) ...[
            const SizedBox(height: 12),
            SectionCard(child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Предыдущие версии (${revisions.length - 1})',
                style: const TextStyle(fontWeight: FontWeight.w700)),
              children: revisions.take(revisions.length - 1).map((revision) {
                final oldChange = revision['mainChange'];
                final oldTitle = oldChange is Map ? oldChange['title'] : null;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Версия ${revision['version'] ?? 1} · $oldTitle'),
                  subtitle: Text('${_formatHistoryDate(revision['generatedAt'])}\n${revision['revisionReason'] ?? ''}'),
                );
              }).toList(),
            )),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SleepDynamicsScreen(database: database),
            )),
            icon: const Icon(Icons.show_chart_rounded),
            label: const Text('Открыть актуальную динамику сна'),
          ),
          const SizedBox(height: 8),
          const Text('Сохранённые значения относятся к указанным датам и версии расчёта. При изменении исходных записей новая версия добавляется отдельно; предыдущий снимок не перезаписывается.',
            style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.45)),
        ],
      ),
    );
  }
}

class SleepChangeHistoryChartScreen extends StatefulWidget {
  const SleepChangeHistoryChartScreen({super.key, required this.database});
  final SleepDatabase database;

  @override
  State<SleepChangeHistoryChartScreen> createState() => _SleepChangeHistoryChartScreenState();
}

class _SleepChangeHistoryChartScreenState extends State<SleepChangeHistoryChartScreen> {
  late Future<List<Map<String, Object?>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.database.getSleepChangeHistory();
  }

  void _openSnapshot(List<Map<String, Object?>> all, Map<String, Object?> selected) {
    final key = selected['periodKey'];
    final revisions = all.where((item) => item['periodKey'] == key).toList()
      ..sort((a, b) => ((a['version'] as int?) ?? 1).compareTo((b['version'] as int?) ?? 1));
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SleepChangeHistoryDetailScreen(database: widget.database, revisions: revisions),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Динамика главных изменений')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _future,
      builder: (context, state) {
        if (state.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (state.hasError) return Center(child: Text('Не удалось загрузить историю: ${state.error}'));
        final all = state.data ?? const <Map<String, Object?>>[];
        final snapshots = _latestMonthlySnapshots(all);
        if (snapshots.isEmpty) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('График появится после сохранения первого месячного сравнения.'),
          ));
        }
        final changes = snapshots.map((item) => item['mainChange'])
          .whereType<Map>().map((item) => Map<String, Object?>.from(item)).toList();
        final kinds = <String>[];
        for (final change in changes) {
          final kind = change['kind'];
          if (kind is String && !kinds.contains(kind)) kinds.add(kind);
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            const ScreenHeader(
              title: 'Динамика главных изменений',
              subtitle: 'Каждый показатель показан отдельно; пропущенные месяцы не соединяются искусственными точками',
              icon: Icons.timeline_rounded,
            ),
            const SizedBox(height: 12),
            if (kinds.isEmpty)
              const SectionCard(child: Text('За сохранённые месяцы пока не выявлено главных изменений. Статусы месяцев сохранены в истории.')),
            ...kinds.map((kind) {
              final sample = changes.firstWhere((item) => item['kind'] == kind);
              final values = snapshots.map((snapshot) {
                final value = snapshot['mainChange'];
                if (value is! Map || value['kind'] != kind || value['delta'] is! num) return null;
                return (value['delta'] as num).toDouble();
              }).toList();
              final title = sample['title'] as String? ?? 'Показатель';
              final unit = sample['unit'] as String? ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SectionCard(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('Изменение, ${unit.isEmpty ? 'без единиц' : unit}. Положительные и отрицательные значения показываются по разные стороны нулевой линии.',
                      style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                    const SizedBox(height: 10),
                    LayoutBuilder(builder: (context, constraints) {
                      final chartWidth = math.max(constraints.maxWidth, snapshots.length * 58.0);
                      final pointWidth = chartWidth / snapshots.length;
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: chartWidth,
                          child: Column(children: [
                            SizedBox(
                              height: 112,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapUp: (details) {
                                  final index = (details.localPosition.dx / chartWidth * snapshots.length)
                                    .floor().clamp(0, snapshots.length - 1);
                                  if (values[index] != null) _openSnapshot(all, snapshots[index]);
                                },
                                child: CustomPaint(
                                  size: Size(chartWidth, 112),
                                  painter: _ChangeSeriesPainter(values),
                                ),
                              ),
                            ),
                            Row(children: [
                              for (final snapshot in snapshots)
                                SizedBox(
                                  width: pointWidth,
                                  child: Text(snapshot['periodKey'] as String? ?? '',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 9, color: AppTheme.muted)),
                                ),
                            ]),
                          ]),
                        ),
                      );
                    }),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (var i = 0; i < snapshots.length; i++)
                          if (values[i] != null)
                            ActionChip(
                              label: Text('${snapshots[i]['periodKey']}: ${_formatHistoryDelta(Map<String, Object?>{'delta': values[i], 'unit': unit})}',
                                style: const TextStyle(fontSize: 10)),
                              onPressed: () => _openSnapshot(all, snapshots[i]),
                            ),
                      ],
                    ),
                  ],
                )),
              );
            }),
            const SizedBox(height: 4),
            const Text('Статусы месяцев без выбранного главного изменения', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...snapshots.where((snapshot) => snapshot['mainChange'] == null).map((snapshot) {
              final status = snapshot['mainChangeStatus'];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(snapshot['periodKey'] as String? ?? 'Период'),
                subtitle: Text(status == 'insufficient_data'
                    ? 'Недостаточно сопоставимых данных'
                    : 'Одного выраженного главного изменения не выявлено'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openSnapshot(all, snapshot),
              );
            }),
            const SizedBox(height: 8),
            const Text('Точки строятся только по сохранённым результатам. Если в конкретном месяце главным был другой показатель, точка в этой серии отсутствует и линия через такой пропуск не проводится. Значения разных метрик не объединяются на общей оси.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.45)),
          ],
        );
      },
    ),
  );
}

class _ChangeSeriesPainter extends CustomPainter {
  const _ChangeSeriesPainter(this.values);
  final List<double?> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final available = values.whereType<double>().toList();
    if (available.isEmpty) return;
    final maxAbs = available.map((value) => value.abs()).reduce((a, b) => a > b ? a : b);
    final scale = maxAbs == 0 ? 1.0 : maxAbs;
    final center = size.height * 0.48;
    final amplitude = size.height * 0.34;
    final baseline = Paint()
      ..color = AppTheme.muted.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, center), Offset(size.width, center), baseline);

    double xAt(int index) => values.length == 1
        ? size.width / 2
        : index * size.width / (values.length - 1);
    double yAt(double value) => center - value / scale * amplitude;

    final line = Paint()
      ..color = AppTheme.teal
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < values.length; i++) {
      final before = values[i - 1];
      final after = values[i];
      if (before == null || after == null) continue;
      canvas.drawLine(Offset(xAt(i - 1), yAt(before)), Offset(xAt(i), yAt(after)), line);
    }
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value == null) continue;
      final point = Offset(xAt(i), yAt(value));
      final paint = Paint()..color = value >= 0 ? AppTheme.teal : const Color(0xFFE58B91);
      canvas.drawCircle(point, 4.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChangeSeriesPainter oldDelegate) =>
      !listEquals(oldDelegate.values, values);
}
