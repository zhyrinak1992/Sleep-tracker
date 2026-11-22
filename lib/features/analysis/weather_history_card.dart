import 'package:flutter/material.dart';

import '../../data/sleep_database.dart';
import '../../data/weather_history_service.dart';
import '../../models/sleep_session.dart';
import '../../models/weather_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class WeatherHistoryCard extends StatefulWidget {
  const WeatherHistoryCard({super.key, required this.database, required this.sessions});
  final SleepDatabase database;
  final List<SleepSession> sessions;

  @override
  State<WeatherHistoryCard> createState() => _WeatherHistoryCardState();
}

class _WeatherHistoryCardState extends State<WeatherHistoryCard> {
  late Future<WeatherLocation?> _locationFuture;
  bool _syncing = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _locationFuture = WeatherHistoryService.instance.loadLocation(database: widget.database);
  }

  Future<void> _chooseLocation() async {
    final controller = TextEditingController();
    List<WeatherLocation> results = [];
    String? error;
    bool searching = false;
    final selected = await showDialog<WeatherLocation>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Место для исторической погоды'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Введи город. Запрос отправится в Open-Meteo, чтобы найти координаты; GPS и точное местоположение телефона не используются.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: AppTheme.muted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) async {
                    setDialogState(() { searching = true; error = null; });
                    try {
                      results = await WeatherHistoryService.instance.searchLocations(controller.text);
                      if (results.isEmpty) error = 'Город не найден. Уточни название.';
                    } catch (e) {
                      error = e.toString();
                    }
                    if (!dialogContext.mounted) return;
                    setDialogState(() => searching = false);
                  },
                  decoration: const InputDecoration(labelText: 'Город', hintText: 'Например, Дубна'),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: searching ? null : () async {
                      setDialogState(() { searching = true; error = null; });
                      try {
                        results = await WeatherHistoryService.instance.searchLocations(controller.text);
                        if (results.isEmpty) error = 'Город не найден. Уточни название.';
                      } catch (e) {
                        error = e.toString();
                      }
                      if (!dialogContext.mounted) return;
                      setDialogState(() => searching = false);
                    },
                    icon: searching
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search, size: 18),
                    label: Text(searching ? 'Поиск…' : 'Найти город'),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: AppTheme.accentPink, fontSize: 11)),
                ],
                if (results.isNotEmpty) ...[
                  const Divider(height: 20),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final item = results[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.displayName, style: const TextStyle(fontSize: 13)),
                          subtitle: Text('${item.latitude.toStringAsFixed(3)}, ${item.longitude.toStringAsFixed(3)} · ${item.timezone}',
                            style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
                          onTap: () => Navigator.pop(dialogContext, item),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          ],
        ),
      ),
    );
    controller.dispose();
    if (selected == null || !mounted) return;
    await WeatherHistoryService.instance.saveLocation(selected, database: widget.database);
    if (!mounted) return;
    setState(() {
      _locationFuture = Future.value(selected);
      _status = 'Выбрано место: ${selected.displayName}.';
    });
  }

  Future<void> _sync() async {
    setState(() { _syncing = true; _status = null; });
    try {
      final result = await WeatherHistoryService.instance.syncSessions(
        sessions: widget.sessions,
        database: widget.database,
      );
      if (!mounted) return;
      setState(() => _status =
        'Обновлено ночей: ${result.nightsUpdated}; с историческими данными: ${result.nightsWithData}; часовых измерений: ${result.hourlySamples}.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Не удалось получить историческую погоду: $error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Погода во время сна', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 5),
      const Text(
        'Исторические данные для выбранного города и ночей с фактическими границами сна: температура, влажность, давление, осадки и ветер. Также доступны восход, закат и длительность светового дня. Текущая погода вместо исторической не подставляется.',
        style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
      ),
      const SizedBox(height: 10),
      FutureBuilder<WeatherLocation?>(
        future: _locationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LinearProgressIndicator();
          }
          final location = snapshot.data;
          if (location == null) {
            return SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _chooseLocation,
                icon: const Icon(Icons.location_city_outlined),
                label: const Text('Выбрать город'),
              ),
            );
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.location_on_outlined, color: AppTheme.teal, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(location.displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              TextButton(onPressed: _chooseLocation, child: const Text('Изменить')),
            ]),
            Text('Часовой пояс: ${location.timezone}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _syncing || widget.sessions.isEmpty ? null : _sync,
                icon: _syncing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_download_outlined, size: 18),
                label: Text(_syncing ? 'Загрузка истории…' : 'Получить историю для выбранного периода'),
              ),
            ),
          ]);
        },
      ),
      if (_status != null) ...[
        const SizedBox(height: 8),
        Text(_status!, style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.35)),
      ],
      const SizedBox(height: 6),
      const Text(
        'Источник: Open-Meteo Historical Weather API. Координаты передаются поставщику только после выбора города и запроса истории. Часовые значения имеют архивное разрешение и могут быть неполными.',
        style: TextStyle(color: AppTheme.muted, fontSize: 10, height: 1.35),
      ),
    ]),
  );
}
