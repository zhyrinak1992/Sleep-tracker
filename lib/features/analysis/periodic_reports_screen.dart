import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/pdf_report_service.dart';
import '../../data/sleep_database.dart';
import '../../theme/app_theme.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/section_card.dart';
import 'periodic_report_service.dart';
import 'sleep_recommendation_text.dart';
import 'periodic_report_export.dart';
import 'tag_insight_preferences.dart';
import 'tag_insight_history.dart';

class PeriodicReportsScreen extends StatefulWidget {
  const PeriodicReportsScreen({super.key, required this.database});
  final SleepDatabase database;
  @override
  State<PeriodicReportsScreen> createState() => _PeriodicReportsScreenState();
}

class _PeriodicReportsScreenState extends State<PeriodicReportsScreen> {
  late Future<List<PeriodicReportSnapshot>> _future;
  late Future<Map<String, Object?>?> _currentInsightFuture;
  TagInsightPreferences _insightPreferences = const TagInsightPreferences();
  bool _preferencesLoading = true;
  String? _preferencesError;

  TagInsightPreferenceStore get _preferenceStore => TagInsightPreferenceStore(
    widget.database.getAppMetadata,
    widget.database.setAppMetadata,
  );

  @override
  void initState() {
    super.initState();
    _future = _load();
    _currentInsightFuture = _loadCurrentInsights();
    _loadInsightPreferences();
  }

  Future<void> _loadInsightPreferences() async {
    try {
      final preferences = await _preferenceStore.load();
      if (!mounted) return;
      setState(() {
        _insightPreferences = preferences;
        _preferencesLoading = false;
        _preferencesError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _preferencesLoading = false;
        _preferencesError = error.toString();
      });
    }
  }

  Future<List<PeriodicReportSnapshot>> _load() async {
    final service = PeriodicReportService(widget.database);
    await service.generateClosedReports();
    return service.loadArchive();
  }

  Future<Map<String, Object?>?> _loadCurrentInsights() =>
      TagInsightHistoryStore(
        widget.database.getAppMetadata,
        widget.database.setAppMetadata,
      ).loadCurrent();

  void _refresh() => setState(() {
    _future = _load();
    _currentInsightFuture = _loadCurrentInsights();
  });

  Future<void> _hideInsight(
    String tagKey, String metricKey, String tagLabel, String metricLabel,
  ) async {
    try {
      final preferences = await _preferenceStore.hide(
        tagKey: tagKey, metricKey: metricKey,
        tagLabel: tagLabel, metricLabel: metricLabel,
      );
      if (mounted) setState(() => _insightPreferences = preferences);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось скрыть закономерность: $error')),
      );
    }
  }

  Future<void> _togglePinInsight(
    String tagKey, String metricKey, String tagLabel, String metricLabel, bool currentlyPinned,
  ) async {
    try {
      final preferences = currentlyPinned
          ? await _preferenceStore.unpin(tagKey: tagKey, metricKey: metricKey)
          : await _preferenceStore.pin(
              tagKey: tagKey, metricKey: metricKey,
              tagLabel: tagLabel, metricLabel: metricLabel,
            );
      if (mounted) setState(() => _insightPreferences = preferences);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось изменить закрепление: $error')),
      );
    }
  }

  Future<void> _restoreInsight(String id) async {
    final preferences = await _preferenceStore.restore(id);
    if (mounted) setState(() => _insightPreferences = preferences);
  }

  Future<void> _showHiddenInsights() async {
    if (_preferencesLoading || _preferencesError != null) return;
    final entries = _insightPreferences.hidden.entries.toList();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Скрытые закономерности'),
        content: entries.isEmpty
            ? const Text('Скрытых закономерностей пока нет.')
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.value.tagLabel),
                      subtitle: Text(entry.value.metricLabel),
                      trailing: TextButton(
                        onPressed: () async {
                          try {
                            await _restoreInsight(entry.key);
                            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                          } catch (error) {
                            if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(content: Text('Не удалось восстановить закономерность: $error')),
                            );
                          }
                        },
                        child: const Text('Вернуть'),
                      ),
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }
  String _monthLabel(DateTime? date) {
    if (date == null) return 'Период неизвестен';
    const months = [
      'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
      'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  String _dateTimeLabel(Object? raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '');
    if (date == null) return 'Дата неизвестна';
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _insightValue(String metricKey, Object? raw) {
    if (raw is! num) return 'нет данных';
    if (metricKey == 'duration' || metricKey == 'sleepLatency') {
      return _duration(raw.toDouble());
    }
    if (metricKey == 'bedtime' || metricKey == 'wakeTime') {
      final minute = raw.round().remainder(1440);
      return '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
    }
    const suffixes = {
      'score': ' / 100',
      'awakenings': ' эпиз.',
      'efficiency': '%',
      'subjectiveQuality': ' / 5',
      'wellbeing': ' / 5',
      'heartRate': ' уд/мин',
      'respiratoryRate': ' вдох/мин',
      'bloodOxygen': '%',
      'hrv': ' мс',
      'roomTemperature': ' °C',
      'roomHumidity': '%',
    };
    return raw.toStringAsFixed(1) + (suffixes[metricKey] ?? '');
  }

  String _insightDifference(String metricKey, Object? raw) {
    if (raw is! num) return 'Разница пока не рассчитана';
    if (metricKey == 'bedtime' || metricKey == 'wakeTime') {
      final minutes = raw.round().abs();
      if (raw == 0) return 'Разницы нет';
      return (raw > 0 ? 'позже на ' : 'раньше на ') + '$minutes мин';
    }
    if (raw == 0) return 'Разницы нет';
    return (raw > 0 ? 'выше на ' : 'ниже на ') +
        _insightValue(metricKey, raw.abs());
  }

  Future<void> _showInsightHistory() async {
    final history = await TagInsightHistoryStore(
      widget.database.getAppMetadata,
      widget.database.setAppMetadata,
    ).loadHistory();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('История закономерностей'),
        content: SizedBox(
          width: 520,
          height: 460,
          child: history.isEmpty
              ? const Center(child: Text('История появится после первого пересчёта анализа.'))
              : ListView.separated(
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final snapshot = history[history.length - index - 1];
                    final start = DateTime.tryParse(
                      snapshot['periodStart'] as String? ?? '',
                    );
                    final insights = (snapshot['insights'] as List? ?? const [])
                        .whereType<Map>()
                        .map((item) => Map<String, Object?>.from(item))
                        .toList();
                    return ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(_monthLabel(start)),
                      subtitle: Text(
                        'Пересчёт ${_dateTimeLabel(snapshot['generatedAt'])} · ${insights.length} закономерностей',
                      ),
                      children: insights.map((insight) {
                        final current = insight['current'] is Map
                            ? Map<String, Object?>.from(insight['current'] as Map)
                            : <String, Object?>{};
                        final last = insight['lastComparable'] is Map
                            ? Map<String, Object?>.from(insight['lastComparable'] as Map)
                            : <String, Object?>{};
                        final metricKey = insight['metricKey'] as String? ?? '';
                        final values = current.isNotEmpty ? current : last;
                        final events = (insight['statusEvents'] as List? ?? const [])
                            .whereType<Map>().toList();
                        return ExpansionTile(
                          tilePadding: const EdgeInsets.only(left: 8),
                          title: Text('${insight['tagLabel']} · ${insight['metricLabel']}'),
                          subtitle: Text(TagInsightHistoryStore.statusLabel(
                            insight['status'] as String?,
                          )),
                          children: [
                            ListTile(
                              dense: true,
                              title: Text(
                                'С отметкой: ${_insightValue(metricKey, values['withTagAverage'])} · ${values['withTagSamples'] ?? 0} ночей',
                              ),
                              subtitle: Text(
                                'Без отметки: ${_insightValue(metricKey, values['withoutTagAverage'])} · ${values['withoutTagSamples'] ?? 0} ночей',
                              ),
                            ),
                            ...events.map((event) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.history_rounded, size: 17),
                              title: Text(TagInsightHistoryStore.statusLabel(
                                event['status'] as String?,
                              )),
                              subtitle: Text(_dateTimeLabel(event['at'])),
                            )),
                          ],
                        );
                      }).toList(),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentInsightsSection() => FutureBuilder<Map<String, Object?>?>(
    future: _currentInsightFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const SizedBox.shrink();
      }
      if (snapshot.hasError) {
        return SectionCard(child: Text(
          'Не удалось загрузить текущие закономерности: ${snapshot.error}',
          style: const TextStyle(color: AppTheme.muted, fontSize: 12),
        ));
      }
      final current = snapshot.data;
      if (current == null) {
        return const SectionCard(child: Text(
          'Текущие закономерности появятся после утреннего отчёта и накопления достаточных данных.',
          style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
        ));
      }
      final all = (current['insights'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, Object?>.from(item))
          .toList();
      final visible = all.where((insight) {
        final tagKey = insight['tagKey'] as String? ?? '';
        final metricKey = insight['metricKey'] as String? ?? '';
        return tagKey.isNotEmpty && metricKey.isNotEmpty &&
            !_insightPreferences.isHidden(
              TagInsightPreferenceStore.identity(tagKey, metricKey),
            );
      }).toList()
        ..sort((a, b) {
          int pinOrder(Map<String, Object?> insight) =>
              _insightPreferences.pinned.indexOf(
                TagInsightPreferenceStore.identity(
                  insight['tagKey'] as String,
                  insight['metricKey'] as String,
                ),
              );
          final aPin = pinOrder(a);
          final bPin = pinOrder(b);
          if (aPin >= 0 && bPin >= 0) return aPin.compareTo(bPin);
          if (aPin >= 0) return -1;
          if (bPin >= 0) return 1;
          return (a['tagLabel'] as String).compareTo(b['tagLabel'] as String);
        });
      final start = DateTime.tryParse(current['periodStart'] as String? ?? '');
      return SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Что может влиять на твой сон',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Период: ${_monthLabel(start)} · сравнение ночей с отметкой и без неё. Статус сопоставляется с предыдущими пересчётами этого же месяца; это не доказательство причин.',
            style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            Text(
              all.isEmpty
                  ? 'Надёжных закономерностей пока не выявлено.'
                  : 'Все выявленные закономерности скрыты. Их можно вернуть из списка скрытых.',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ...visible.map((insight) {
            final tagKey = insight['tagKey'] as String;
            final tagLabel = insight['tagLabel'] as String;
            final metricKey = insight['metricKey'] as String;
            final metricLabel = insight['metricLabel'] as String;
            final identity = TagInsightPreferenceStore.identity(tagKey, metricKey);
            final pinned = _insightPreferences.pinned.contains(identity);
            final currentValues = insight['current'] is Map
                ? Map<String, Object?>.from(insight['current'] as Map)
                : <String, Object?>{};
            final lastValues = insight['lastComparable'] is Map
                ? Map<String, Object?>.from(insight['lastComparable'] as Map)
                : <String, Object?>{};
            final values = currentValues.isNotEmpty ? currentValues : lastValues;
            final difference = currentValues['difference'];
            final status = insight['status'] as String?;
            final samplesWith = values['withTagSamples'] ?? 0;
            final samplesWithout = values['withoutTagSamples'] ?? 0;
            final differenceText = status == 'insufficientData'
                ? 'Последнее сопоставимое различие: ${_insightDifference(metricKey, lastValues['difference'])}'
                : status == 'noLongerObserved'
                    ? 'Прежнее направление различия больше не наблюдается'
                    : _insightDifference(metricKey, difference);
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(left: 10, right: 4, bottom: 6),
                title: Text(
                  '$tagLabel · $metricLabel',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${TagInsightHistoryStore.statusLabel(status)} · с отметкой $samplesWith / без отметки $samplesWithout ночей',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: PopupMenuButton<String>(
                  enabled: !_preferencesLoading && _preferencesError == null,
                  tooltip: 'Действия с закономерностью',
                  onSelected: (action) {
                    if (action == 'hide') {
                      _hideInsight(tagKey, metricKey, tagLabel, metricLabel);
                    } else if (action == 'pin' || action == 'unpin') {
                      _togglePinInsight(
                        tagKey, metricKey, tagLabel, metricLabel, action == 'unpin',
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: pinned ? 'unpin' : 'pin',
                      child: Text(pinned ? 'Снять закрепление' : 'Закрепить'),
                    ),
                    const PopupMenuItem(
                      value: 'hide',
                      child: Text('Скрыть'),
                    ),
                  ],
                ),
                children: [
                  _ReportLine(
                    label: 'Среднее с отметкой',
                    value: _insightValue(metricKey, values['withTagAverage']),
                  ),
                  _ReportLine(
                    label: 'Среднее без отметки',
                    value: _insightValue(metricKey, values['withoutTagAverage']),
                  ),
                  _ReportLine(label: 'Наблюдаемое различие', value: differenceText),
                  if (status == 'insufficientData')
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: Text(
                        'Недостаточно сопоставимых наблюдений. Это не считается опровержением прежней закономерности.',
                        style: TextStyle(color: AppTheme.muted, fontSize: 11),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ));
    },
  );

  Future<void> _export(PeriodicReportSnapshot report) async {
    await PdfReportService.exportPeriodicSnapshot(report.data, report.title);
  }
  Future<void> _exportCsv(PeriodicReportSnapshot report) async {
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path, 'SleepTracker-${report.id}.csv'));
    await file.writeAsString(PeriodicReportExport.toCsv(report.data), encoding: utf8, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv', name: p.basename(file.path))],
      subject: 'Табличный отчёт Sleep Tracker',
      text: 'Табличные данные сохранённого отчёта Sleep Tracker.',
    );
  }
  String _duration(double? minutes) {
    if (minutes == null) return 'Нет данных';
    final value = minutes.round();
    return (value ~/ 60).toString() + ' ч ' + (value % 60).toString() + ' мин';
  }
  String _average(double? value, String suffix) =>
      value == null ? 'Нет данных' : value.toStringAsFixed(1) + suffix;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Периодические отчёты'), actions: [
      IconButton(tooltip: 'Обновить', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
    ]),
    body: FutureBuilder<List<PeriodicReportSnapshot>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Не удалось сформировать архив отчётов: ' + snapshot.error.toString()),
        ));
        final reports = snapshot.data ?? const <PeriodicReportSnapshot>[];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            const ScreenHeader(title: 'История отчётов', subtitle: 'Сохранённые сводки по завершённым периодам', icon: Icons.auto_graph_rounded),
            const SizedBox(height: 4),
            _buildCurrentInsightsSection(),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _showInsightHistory,
                    icon: const Icon(Icons.history_rounded, size: 17),
                    label: const Text('История статусов'),
                  ),
                  TextButton.icon(
                    onPressed: _preferencesLoading || _preferencesError != null ? null : _showHiddenInsights,
                    icon: const Icon(Icons.visibility_off_outlined, size: 17),
                    label: Text('Скрытые закономерности (${_insightPreferences.hidden.length})'),
                  ),
                ],
              ),
            ),
            if (_preferencesError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Настройки закономерностей недоступны: $_preferencesError',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
              ),
            const SizedBox(height: 4),
            if (reports.isEmpty)
              const SectionCard(child: Text(
                'Здесь будут сохраняться недельные, месячные, квартальные, полугодовые и годовые отчёты после завершения соответствующих периодов.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12),
              )),
            ...reports.map((report) => _ReportCard(
              report: report,
              duration: _duration(report.averageSleepMinutes),
              average: _average,
              onExport: () => _export(report),
              onExportCsv: () => _exportCsv(report),
              insightPreferences: _insightPreferences,
              canManageInsights: !_preferencesLoading && _preferencesError == null,
              onHideInsight: _hideInsight,
              onTogglePinInsight: _togglePinInsight,
            )),
            const SizedBox(height: 10),
            const Text(
              'Отчёты создаются при открытии этого раздела. Если приложение было закрыто в день окончания периода, пропущенные отчёты будут сформированы при следующем открытии. iOS не гарантирует запуск приложения в фоне по расписанию. Оценка 0–100 рассчитывается по личному диапазону сна за предыдущие 90 дней и доступным измерениям. Недостающие веса перераспределяются; при менее чем двух компонентах или доступном исходном весе ниже 50% оценка скрывается. Это не медицинский показатель.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45),
            ),
          ],
        );
      },
    ),
  );
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report, required this.duration, required this.average,
    required this.onExport, required this.onExportCsv,
    required this.insightPreferences, required this.canManageInsights,
    required this.onHideInsight, required this.onTogglePinInsight,
  });
  final PeriodicReportSnapshot report;
  final String duration;
  final String Function(double?, String) average;
  final VoidCallback onExport;
  final VoidCallback onExportCsv;
  final TagInsightPreferences insightPreferences;
  final bool canManageInsights;
  final Future<void> Function(String, String, String, String) onHideInsight;
  final Future<void> Function(String, String, String, String, bool) onTogglePinInsight;

  @override
  Widget build(BuildContext context) {
    final previous = report.data['previous'] is Map
      ? Map<String, Object?>.from(report.data['previous'] as Map) : <String, Object?>{};
    final categories = report.data['audioCategories'] is Map
      ? Map<String, Object?>.from(report.data['audioCategories'] as Map) : <String, Object?>{};
    final notes = report.data['notes'] is List
      ? (report.data['notes'] as List).whereType<Map>().toList() : const <Map>[];
    final months = report.data['months'] is List
      ? (report.data['months'] as List).whereType<Map>().toList() : const <Map>[];
    final weeklyTrend = report.data['weeklyTrend'] is List
      ? (report.data['weeklyTrend'] as List).whereType<Map>().toList() : const <Map>[];
    final trendPoints = report.data['trendPoints'] is List
      ? (report.data['trendPoints'] as List).whereType<Map>().toList() : const <Map>[];
    final weekdayTrend = report.data['weekdayTrend'] is List
      ? (report.data['weekdayTrend'] as List).whereType<Map>().toList() : const <Map>[];
    final weekdayPatterns = report.data['weekdayPatterns'] is List
      ? (report.data['weekdayPatterns'] as List).whereType<Map>().toList() : const <Map>[];
    final score = report.data['score'] is Map ? Map<String, Object?>.from(report.data['score'] as Map) : <String, Object?>{};
    final tagPatterns = report.data['tagPatterns'] is Map
      ? Map<String, Object?>.from(report.data['tagPatterns'] as Map)
      : <String, Object?>{};
    final currentTagPatterns = tagPatterns['current'] is List
      ? (tagPatterns['current'] as List).whereType<Map>().toList() : const <Map>[];
    final visibleCurrentTagPatterns = currentTagPatterns.map((rawPattern) {
      final pattern = Map<String, Object?>.from(rawPattern);
      final tagKey = (pattern['tagKey'] ?? '').toString();
      final metrics = pattern['metrics'] is Map
          ? Map<String, Object?>.from(pattern['metrics'] as Map)
          : <String, Object?>{};
      if (tagKey.isNotEmpty) {
        metrics.removeWhere((metricKey, _) => insightPreferences.isHidden(
          TagInsightPreferenceStore.identity(tagKey, metricKey),
        ));
      }
      return <String, Object?>{...pattern, 'metrics': metrics};
    }).where((pattern) =>
      pattern['metrics'] is Map && (pattern['metrics'] as Map).isNotEmpty
    ).toList();
    final previousTagPatterns = tagPatterns['previous'] is List
      ? (tagPatterns['previous'] as List).whereType<Map>().toList() : const <Map>[];
    final rankedInsights = report.data['rankedInsights'] is List
      ? (report.data['rankedInsights'] as List).whereType<Map>().map((item) => Map<String, Object?>.from(item)).toList()
      : <Map<String, Object?>>[];
    final visibleRankedInsights = rankedInsights.where((insight) {
      final tagKey = insight['tagKey'] as String?;
      final metricKey = insight['metricKey'] as String?;
      if (tagKey == null || metricKey == null) return true;
      return !insightPreferences.isHidden(TagInsightPreferenceStore.identity(tagKey, metricKey));
    }).toList()..sort((a, b) {
      int pinOrder(Map<String, Object?> insight) {
        final tagKey = insight['tagKey'] as String?;
        final metricKey = insight['metricKey'] as String?;
        if (tagKey == null || metricKey == null) return -1;
        return insightPreferences.pinned.indexOf(TagInsightPreferenceStore.identity(tagKey, metricKey));
      }
      final aPin = pinOrder(a);
      final bPin = pinOrder(b);
      if (aPin >= 0 && bPin >= 0) return aPin.compareTo(bPin);
      if (aPin >= 0) return -1;
      if (bPin >= 0) return 1;
      return ((a['rank'] as num?) ?? 0).compareTo((b['rank'] as num?) ?? 0);
    });
    final scoreComponents = score['components'] is Map ? Map<String, Object?>.from(score['components'] as Map) : <String, Object?>{};
    final previousScore = previous['score'] is Map ? Map<String, Object?>.from(previous['score'] as Map) : <String, Object?>{};
    final shortest = report.data['shortestAverageMonth'];
    final longest = report.data['longestAverageMonth'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(report.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            IconButton(tooltip: 'Экспорт PDF', onPressed: onExport, icon: const Icon(Icons.picture_as_pdf_outlined)),
            IconButton(tooltip: 'Экспорт CSV', onPressed: onExportCsv, icon: const Icon(Icons.table_chart_outlined)),
          ]),
          const SizedBox(height: 10),
          _ReportLine(label: 'Завершённых ночей', value: report.nights.toString()),
          _ReportLine(
            label: 'Средняя оценка сна · ' + (score['samples'] ?? 0).toString() + ' ночей',
            value: score['average'] is num ? (score['average'] as num).toStringAsFixed(0) + ' / 100' : 'Недостаточно данных',
          ),
          if (scoreComponents.isNotEmpty) ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Состав оценки сна', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            children: scoreComponents.entries.map((entry) {
              final component = entry.value is Map ? Map<String, Object?>.from(entry.value as Map) : <String, Object?>{};
              final value = component['average'];
              return _ReportLine(
                label: (component['label'] ?? entry.key).toString() + ' · ' + (component['samples'] ?? 0).toString() + ' ночей',
                value: value is num ? value.toStringAsFixed(0) + ' / 100' : 'Нет данных',
              );
            }).toList(),
          ),
          if (visibleRankedInsights.isNotEmpty) ...[
            const Divider(height: 22),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: true,
              title: const Text('Что может влиять на твой сон', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              subtitle: const Text('Ранжирование по повторяемости, объёму выборки и размеру различия', style: TextStyle(fontSize: 11)),
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Это статистические наблюдения, а не доказательство причин. Повторяющимся считается сходное направление различия в двух соседних периодах. Сравниваются ночи с выбранной отметкой и без неё.',
                    style: TextStyle(fontSize: 11, height: 1.4, color: AppTheme.muted),
                  ),
                ),
                ...visibleRankedInsights.map((insight) {
                  final metricKey = insight['metricKey'] as String? ?? '';
                  final difference = insight['difference'] as num? ?? 0;
                  final withAverage = insight['withTagAverage'];
                  final withoutAverage = insight['withoutTagAverage'];
                  final samplesWith = insight['withTagSamples'] ?? 0;
                  final samplesWithout = insight['withoutTagSamples'] ?? 0;
                  String display(Object? raw) {
                    if (raw is! num) return 'нет данных';
                    if (metricKey == 'duration' || metricKey == 'sleepLatency') {
                      final minutes = raw.round();
                      return '${minutes ~/ 60} ч ${minutes % 60} мин';
                    }
                    if (metricKey == 'bedtime' || metricKey == 'wakeTime') {
                      final minute = raw.round().remainder(1440);
                      return '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
                    }
                    const suffixes = {
                      'score': ' / 100', 'awakenings': ' эпиз.',
                      'efficiency': '%', 'subjectiveQuality': ' / 5',
                      'wellbeing': ' / 5', 'heartRate': ' уд/мин',
                      'respiratoryRate': ' вдох/мин', 'bloodOxygen': '%',
                      'hrv': ' мс', 'roomTemperature': ' °C',
                      'roomHumidity': '%',
                    };
                    return raw.toStringAsFixed(1) + (suffixes[metricKey] ?? '');
                  }
                  String deltaText() {
                    if (metricKey == 'bedtime' || metricKey == 'wakeTime') {
                      final mins = difference.round().abs();
                      return (difference > 0 ? 'позже на ' : 'раньше на ') + mins.toString() + ' мин';
                    }
                    return (difference > 0 ? 'выше на ' : 'ниже на ') + display(difference.abs());
                  }
                  final repeated = insight['repeatsPreviousPeriod'] == true;
                  final recommendation = SleepRecommendationText.forObservedPattern(
                    tagLabel: (insight['tagLabel'] ?? '').toString(),
                    metricKey: metricKey,
                    difference: difference.toDouble(),
                  );
                  final withObservations = insight['withTagObservations'] is List
                    ? (insight['withTagObservations'] as List).whereType<Map>().toList() : const <Map>[];
                  final withoutObservations = insight['withoutTagObservations'] is List
                    ? (insight['withoutTagObservations'] as List).whereType<Map>().toList() : const <Map>[];
                  Widget observations(String title, List<Map> values) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
                      ...values.map((item) {
                        final date = DateTime.tryParse(item['startedAt'] as String? ?? '');
                        final dateText = date == null ? 'Дата неизвестна' :
                          '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
                        return _ReportLine(label: dateText, value: display(item['value']));
                      }),
                    ]),
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(left: 10, right: 4, bottom: 8),
                      title: Row(children: [
                        Expanded(child: Text(
                          '${insight['rank']}. ${insight['tagLabel']} · ${insight['metricLabel']}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        )),
                        PopupMenuButton<String>(
                          enabled: canManageInsights,
                          tooltip: 'Действия с закономерностью',
                          onSelected: (action) {
                            final tagKey = (insight['tagKey'] ?? '').toString();
                            final tagLabel = (insight['tagLabel'] ?? '').toString();
                            final metricLabel = (insight['metricLabel'] ?? metricKey).toString();
                            if (tagKey.isEmpty || metricKey.isEmpty) return;
                            if (action == 'hide') {
                              onHideInsight(tagKey, metricKey, tagLabel, metricLabel);
                            } else if (action == 'pin' || action == 'unpin') {
                              onTogglePinInsight(tagKey, metricKey, tagLabel, metricLabel, action == 'unpin');
                            }
                          },
                          itemBuilder: (context) {
                            final pinned = insightPreferences.isPinned(TagInsightPreferenceStore.identity(
                              (insight['tagKey'] ?? '').toString(), metricKey,
                            ));
                            return [
                              PopupMenuItem(value: pinned ? 'unpin' : 'pin',
                                child: Text(pinned ? 'Снять закрепление' : 'Закрепить')),
                              const PopupMenuItem(value: 'hide', child: Text('Скрыть')),
                            ];
                          },
                        ),
                      ]),
                      subtitle: Text(
                        '${deltaText()} · выборки $samplesWith / $samplesWithout ночей' +
                        (repeated ? ' · повторяется' : ' · только текущий период') +
                        (insightPreferences.isPinned(TagInsightPreferenceStore.identity(
                          (insight['tagKey'] ?? '').toString(), metricKey,
                        )) ? ' · закреплено' : ''),
                        style: const TextStyle(fontSize: 11),
                      ),
                      children: [
                        _ReportLine(label: 'С отметкой', value: display(withAverage) + ' · n=$samplesWith'),
                        _ReportLine(label: 'Без отметки', value: display(withoutAverage) + ' · n=$samplesWithout'),
                        if (recommendation != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Что можно проверить',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
                                const SizedBox(height: 3),
                                Text(recommendation,
                                  style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
                              ],
                            ),
                          ),
                        if (insight['previousDifference'] is num)
                          _ReportLine(
                            label: 'Разница в предыдущем периоде',
                            value: (insight['previousDifference'] as num).toStringAsFixed(1),
                          ),
                        observations('Ночи с отметкой', withObservations),
                        observations('Ночи без отметки', withoutObservations),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ],
          if (visibleCurrentTagPatterns.isNotEmpty) ...[
            const Divider(height: 22),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Персональные закономерности по отметкам', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text('Наблюдаемое сравнение ночей с отметкой и без неё', style: TextStyle(fontSize: 11)),
              children: visibleCurrentTagPatterns.map((rawPattern) {
                final pattern = Map<String, Object?>.from(rawPattern);
                final key = pattern['tagKey'];
                final previousPattern = previousTagPatterns.where((item) => item['tagKey'] == key).toList();
                final previousMetrics = previousPattern.isEmpty || previousPattern.first['metrics'] is! Map
                  ? <String, Object?>{}
                  : Map<String, Object?>.from(previousPattern.first['metrics'] as Map);
                final metrics = pattern['metrics'] is Map
                  ? Map<String, Object?>.from(pattern['metrics'] as Map) : <String, Object?>{};
                String formatMetric(String metricKey, String suffix) {
                  final current = metrics[metricKey] is Map
                    ? Map<String, Object?>.from(metrics[metricKey] as Map) : <String, Object?>{};
                  final previous = previousMetrics[metricKey] is Map
                    ? Map<String, Object?>.from(previousMetrics[metricKey] as Map) : <String, Object?>{};
                  String value(Object? raw) {
                    if (metricKey == 'duration') return _formatDuration(raw);
                    if (raw is! num) return 'нет данных';
                    if (metricKey == 'bedtime' || metricKey == 'wakeTime') {
                      final minute = raw.round().remainder(1440);
                      return '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
                    }
                    return raw.toStringAsFixed(1) + suffix;
                  }
                  final difference = current['difference'];
                  final deltaSuffix = metricKey == 'bedtime' || metricKey == 'wakeTime' ? ' мин' : suffix;
                  final delta = difference is num
                    ? ' · разница ' + (difference > 0 ? '+' : '') + difference.toStringAsFixed(1) + deltaSuffix
                    : ' · недостаточно данных для сравнения';
                  return 'С отметкой: ' + value(current['withTagAverage']) +
                    ' (n=' + (current['withTagSamples'] ?? 0).toString() + '); без отметки: ' +
                    value(current['withoutTagAverage']) + ' (n=' +
                    (current['withoutTagSamples'] ?? 0).toString() + ')' + delta +
                    '. Ранее: ' + value(previous['withTagAverage']) + ' / ' +
                    value(previous['withoutTagAverage']) + '.';
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((pattern['label'] ?? key ?? 'Отметка').toString() +
                      ' · ' + (pattern['withTagNights'] ?? 0).toString() + ' ночей с отметкой',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('Продолжительность: ' + formatMetric('duration', ' мин'),
                      style: const TextStyle(fontSize: 11, height: 1.4)),
                    Text('Оценка сна: ' + formatMetric('score', ' балла'),
                      style: const TextStyle(fontSize: 11, height: 1.4)),
                    for (final item in const <(String, String, String)>[
                      ('awakenings', 'Пробуждения', ' эпиз.'),
                      ('efficiency', 'Эффективность сна', '%'),
                      ('sleepLatency', 'Засыпание · задержка', ' мин'),
                      ('subjectiveQuality', 'Субъективное качество', ' / 5'),
                      ('wellbeing', 'Утреннее самочувствие', ' / 5'),
                      ('bedtime', 'Время засыпания', ''),
                      ('wakeTime', 'Время пробуждения', ''),
                      ('heartRate', 'Пульс', ' уд/мин'),
                      ('respiratoryRate', 'Частота дыхания', ' вдох/мин'),
                      ('bloodOxygen', 'Насыщение кислородом', '%'),
                      ('hrv', 'Вариабельность пульса SDNN', ' мс'),
                      ('roomTemperature', 'Температура датчика', ' °C'),
                      ('roomHumidity', 'Влажность датчика', '%'),
                    ])
                      if (metrics.containsKey(item.$1))
                        Text(item.$2 + ': ' + formatMetric(item.$1, item.$3),
                          style: const TextStyle(fontSize: 11, height: 1.4)),
                  ]),
                );
              }).toList(),
            ),
          ],
          if (report.kind == 'year' && report.totalSleepMinutes != null)
            _ReportLine(label: 'Суммарная продолжительность сна', value: _formatDuration(report.totalSleepMinutes)),
          _ReportLine(label: 'Средняя продолжительность сна · ' + (report.data['sleepDurationSamples'] ?? 0).toString() + ' измерений', value: duration),
          _ReportLine(label: 'Время в постели · ' + (report.data['timeInBedSamples'] ?? 0).toString() + ' ночей', value: _formatDuration(report.averageTimeInBedMinutes)),
          _ReportLine(label: 'Эффективность · ' + (report.data['efficiencySamples'] ?? 0).toString() + ' ночей', value: average(report.averageEfficiency, '%')),
          _ReportLine(label: 'Пробуждения · ' + (report.data['awakeningSamples'] ?? 0).toString() + ' ночей', value: average(report.averageAwakenings, '')),
          _ReportLine(label: 'Субъективное качество · ' + (report.data['qualitySamples'] ?? 0).toString() + ' оценок', value: average(report.averageQuality, ' / 5')),
          _ReportLine(label: 'Самочувствие · ' + (report.data['wellbeingSamples'] ?? 0).toString() + ' оценок', value: average(report.averageWellbeing, ' / 5')),
          _ReportLine(label: 'Звуковые события', value: (report.data['audioEventCount'] ?? 0).toString()),
          _ReportLine(label: 'Заметки', value: (report.data['noteCount'] ?? 0).toString()),
          if (previous.isNotEmpty) ...[
            const Divider(height: 22),
            const Text('Сравнение с предыдущим периодом', style: TextStyle(fontWeight: FontWeight.w600)),
            _ReportLine(label: 'Ночей', value: report.nights.toString() + ' · ранее ' + (previous['nights'] ?? 0).toString()),
            _ReportLine(label: 'Средняя оценка сна', value: (score['average'] is num ? (score['average'] as num).toStringAsFixed(0) + ' / 100' : 'Нет данных') + ' · ранее ' + (previousScore['average'] is num ? (previousScore['average'] as num).toStringAsFixed(0) + ' / 100' : 'Нет данных')),
            _ReportLine(label: 'Средняя продолжительность сна', value: duration + ' · ранее ' + _formatDuration(previous['averageSleepMinutes']) + ' (' + (previous['sleepDurationSamples'] ?? 0).toString() + ' изм.)'),
            _ReportLine(label: 'Время в постели', value: _formatDuration(report.averageTimeInBedMinutes) + ' · ранее ' + _formatDuration(previous['averageTimeInBedMinutes']) + ' (' + (previous['timeInBedSamples'] ?? 0).toString() + ' ночей)'),
            _ReportLine(label: 'Эффективность', value: _formatPercent(report.averageEfficiency) + ' · ранее ' + _formatPercent(_number(previous['averageEfficiency'])) + ' (' + (previous['efficiencySamples'] ?? 0).toString() + ' ночей)'),
            _ReportLine(label: 'Пробуждения', value: _formatNumber(report.averageAwakenings) + ' · ранее ' + _formatNumber(_number(previous['averageAwakenings'])) + ' (' + (previous['awakeningSamples'] ?? 0).toString() + ' ночей)'),
            _ReportLine(label: 'Качество сна', value: _formatScale(report.averageQuality) + ' · ранее ' + _formatScale(_number(previous['averageQuality'])) + ' (' + (previous['qualitySamples'] ?? 0).toString() + ' оценок)'),
            _ReportLine(label: 'Самочувствие', value: _formatScale(report.averageWellbeing) + ' · ранее ' + _formatScale(_number(previous['averageWellbeing'])) + ' (' + (previous['wellbeingSamples'] ?? 0).toString() + ' оценок)'),
          ],
          if (notes.isNotEmpty) ...[
            const Divider(height: 22),
            const Text('Заметки за период', style: TextStyle(fontWeight: FontWeight.w600)),
            ...notes.map((note) => Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(_formatNoteDate(DateTime.parse(note['sessionStartedAt'] as String)) + ': ' + (note['text'] as String? ?? ''),
                style: const TextStyle(fontSize: 12, height: 1.4)),
            )),
          ],
          if (categories.isNotEmpty) ...[
            const Divider(height: 22),
            const Text('Категории звуковых событий', style: TextStyle(fontWeight: FontWeight.w600)),
            ...categories.entries.map((entry) => _ReportLine(label: entry.key, value: entry.value.toString())),
          ],
          if (trendPoints.isNotEmpty) ...[
            const Divider(height: 22),
            _InteractiveSleepTrendChart(
              title: report.kind == 'year' ? 'Динамика сна по месяцам'
                : report.kind == 'month' ? 'Динамика сна по неделям'
                : 'Динамика сна по дням',
              points: trendPoints,
            ),
          ],
          if (weekdayTrend.isNotEmpty) ...[
            const SizedBox(height: 10),
            _InteractiveSleepTrendChart(
              title: 'Длительность сна по дням недели',
              points: weekdayTrend,
            ),
          ],
          if (months.isNotEmpty) ...[
            const Divider(height: 22),
            const Text('Динамика по месяцам', style: TextStyle(fontWeight: FontWeight.w600)),
            ...months.map((month) {
              final index = month['month'] as int;
              final monthScore = month['score'] is Map ? Map<String, Object?>.from(month['score'] as Map) : <String, Object?>{};
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _ReportLine(
                  label: PeriodicReportSnapshot.monthName(index) + ' · ' + PdfReportService.monthNightCount(Map<String, Object?>.from(month)).toString() + ' ночей',
                  value: _formatDuration(month['averageSleepMinutes']),
                ),
                _ReportLine(
                  label: '  Оценка сна · ' + (monthScore['samples'] ?? 0).toString() + ' ночей',
                  value: monthScore['average'] is num ? (monthScore['average'] as num).toStringAsFixed(0) + ' / 100' : 'Нет данных',
                ),
                if (month['averageEfficiency'] is num)
                  _ReportLine(label: '  Эффективность · ' + (month['efficiencySamples'] ?? 0).toString() + ' измерений', value: _formatPercent(_number(month['averageEfficiency']))),
                if (month['averageAwakenings'] is num)
                  _ReportLine(label: '  Пробуждения · ' + (month['awakeningSamples'] ?? 0).toString() + ' ночей', value: _formatNumber(_number(month['averageAwakenings']))),
                if (month['averageQuality'] is num)
                  _ReportLine(label: '  Качество сна · ' + (month['qualitySamples'] ?? 0).toString() + ' оценок', value: _formatScale(_number(month['averageQuality']))),
                if (month['averageWellbeing'] is num)
                  _ReportLine(label: '  Самочувствие · ' + (month['wellbeingSamples'] ?? 0).toString() + ' оценок', value: _formatScale(_number(month['averageWellbeing']))),
              ]);
            }),
            if (shortest is int && longest is int)
              Text(
                'Меньшая средняя длительность: ' + PeriodicReportSnapshot.monthName(shortest) +
                '. Большая средняя длительность: ' + PeriodicReportSnapshot.monthName(longest) +
                '. Критерий — средняя продолжительность при наличии не менее 3 ночей в месяце; это не оценка здоровья.',
                style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
              ),
          ],
          if (weeklyTrend.isNotEmpty) ...[
            const Divider(height: 22),
            const Text('Динамика внутри месяца', style: TextStyle(fontWeight: FontWeight.w600)),
            ...weeklyTrend.map((bucket) => _ReportLine(
              label: 'Дни ' + (bucket['dayFrom'] ?? '').toString() + '–' + (bucket['dayTo'] ?? '').toString() +
                ' · ' + (bucket['sleepDurationSamples'] ?? 0).toString() + ' ночей',
              value: _formatDuration(bucket['averageSleepMinutes']),
            )),
          ],
          if (weekdayPatterns.isNotEmpty) ...[
            const Divider(height: 22),
            const Text('Средняя длительность по дням недели', style: TextStyle(fontWeight: FontWeight.w600)),
            ...weekdayPatterns.map((pattern) => _ReportLine(
              label: (pattern['label'] ?? 'День').toString() + ' · ' + (pattern['samples'] ?? 0).toString() + ' ночей',
              value: _formatDuration(pattern['averageSleepMinutes']),
            )),
            const Text('Показываются только группы минимум с тремя фактическими измерениями; это описательная статистика, а не причинный вывод.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
          ],
          const SizedBox(height: 6),
          Text('Выборка: ' + report.nights.toString() + ' ночей. Показатели рассчитываются только при наличии соответствующих измерений.',
            style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
        ],
      )),
    );
  }

  static String _formatNoteDate(DateTime date) =>
      date.day.toString() + ' ' + PeriodicReportSnapshot.monthName(date.month) + ' ' + date.year.toString();

  static double? _number(Object? value) => value is num ? value.toDouble() : null;

  static String _formatPercent(double? value) => value == null ? 'Нет данных' : value.toStringAsFixed(1) + '%';
  static String _formatNumber(double? value) => value == null ? 'Нет данных' : value.toStringAsFixed(1);
  static String _formatScale(double? value) => value == null ? 'Нет данных' : value.toStringAsFixed(1) + ' / 5';

  static String _formatDuration(Object? value) {
    if (value is! num) return 'Нет данных';
    final minutes = value.round();
    return minutes.toString() + ' мин (' + (minutes ~/ 60).toString() + ' ч ' + (minutes % 60).toString() + ' мин)';
  }
}

class _InteractiveSleepTrendChart extends StatefulWidget {
  const _InteractiveSleepTrendChart({required this.title, required this.points});
  final String title;
  final List<Map> points;
  @override
  State<_InteractiveSleepTrendChart> createState() => _InteractiveSleepTrendChartState();
}

class _InteractiveSleepTrendChartState extends State<_InteractiveSleepTrendChart> {
  int? _selectedIndex;
  String _duration(Object? raw) {
    if (raw is! num) return 'Нет данных';
    final minutes = raw.round();
    return '${minutes ~/ 60} ч ${minutes % 60} мин';
  }
  @override
  Widget build(BuildContext context) {
    final valid = widget.points.where((point) => point['sleepMinutes'] is num).toList();
    if (valid.isEmpty) return const SizedBox.shrink();
    final maximum = valid.map((point) => (point['sleepMinutes'] as num).toDouble())
      .fold<double>(0, (a, b) => a > b ? a : b);
    final selected = _selectedIndex != null && _selectedIndex! < valid.length
      ? valid[_selectedIndex!] : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      const SizedBox(height: 6),
      const Text('Нажми на столбец, чтобы открыть значения ночей в выбранном периоде.',
        style: TextStyle(color: AppTheme.muted, fontSize: 11)),
      const SizedBox(height: 12),
      SizedBox(height: 142, child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var index = 0; index < valid.length; index++)
            Expanded(child: InkWell(
              onTap: () => setState(() => _selectedIndex = index),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(_duration(valid[index]['sleepMinutes']),
                    style: const TextStyle(fontSize: 8, color: AppTheme.muted),
                    maxLines: 1, overflow: TextOverflow.clip),
                  const SizedBox(height: 4),
                  Expanded(child: Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: double.infinity,
                      height: maximum <= 0 ? 2 :
                        78 * (valid[index]['sleepMinutes'] as num).toDouble() / maximum,
                      decoration: BoxDecoration(
                        color: _selectedIndex == index
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.primary.withOpacity(0.38),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                      ),
                    ),
                  )),
                  const SizedBox(height: 5),
                  Text((valid[index]['label'] ?? '—').toString(),
                    style: TextStyle(fontSize: 9,
                      fontWeight: _selectedIndex == index ? FontWeight.w700 : FontWeight.normal,
                      color: _selectedIndex == index ? Theme.of(context).colorScheme.primary : AppTheme.muted),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            )),
        ],
      )),
      if (selected != null) ...[
        const Divider(height: 18),
        Text('${selected['label'] ?? 'Выбранный период'} · ${_duration(selected['sleepMinutes'])}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        Text('Измерений: ${selected['samples'] ?? 0}',
          style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
        if (selected['nights'] is List)
          ...(selected['nights'] as List).whereType<Map>().map((night) {
            final date = DateTime.tryParse(night['startedAt'] as String? ?? '');
            final dateLabel = date == null ? 'Дата неизвестна'
              : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
            final values = <String>[];
            if (night['score'] is num) values.add('оценка ${(night['score'] as num).toStringAsFixed(0)}');
            if (night['efficiency'] is num) values.add('эффективность ${(night['efficiency'] as num).toStringAsFixed(0)}%');
            if (night['quality'] is num) values.add('качество ${(night['quality'] as num).toStringAsFixed(1)}/5');
            if (night['wellbeing'] is num) values.add('самочувствие ${(night['wellbeing'] as num).toStringAsFixed(1)}/5');
            return _ReportLine(label: dateLabel,
              value: _duration(night['sleepMinutes']) + (values.isEmpty ? '' : ' · ' + values.join(' · ')));
          }),
      ],
    ]);
  }
}

class _ReportLine extends StatelessWidget {
  const _ReportLine({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 13))),
      const SizedBox(width: 12),
      Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
    ]),
  );
}
