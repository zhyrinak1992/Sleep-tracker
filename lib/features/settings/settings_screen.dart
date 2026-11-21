import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:io';

import '../../data/backup_service.dart';
import '../../data/apple_health_service.dart';
import '../../data/audio_observation_service.dart';
import '../../data/pdf_report_service.dart';
import '../../data/sleep_database.dart';
import '../../data/notification_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось выполнить операцию: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncAppleHealth() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await AppleHealthService.instance.syncRecentSleep();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Apple Health: найдено ночей — ${result.found}, добавлено новых — ${result.imported}.'),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Не удалось получить данные Apple Health: $error'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  Future<void> _startAudioClip() async {
    try {
      await AudioObservationService.instance.startObservation();

    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось начать запись: $error')));
    }
  }

  Future<void> _stopAudioClip() async {
    try {
      await AudioObservationService.instance.stopObservation();

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Аудионаблюдение остановлено. Сохранённые события переданы классификатору; при необходимости категорию можно исправить вручную.')));
    } catch (error) {

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось сохранить фрагмент: $error')));
    }
  }

  Future<void> _createBackup() => _run(
    BackupService.instance.exportToFiles,
    'Подготовлена резервная копия. Выберите «Сохранить в Файлы».',
  );

  Future<void> _restoreBackup() async {
    if (_busy) return;
    final merge = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Способ восстановления'),
        content: const Text(
          'Выберите, как обработать данные из резервной копии. При объединении '
          'существующие записи на этом iPhone сохраняются, а недостающие добавляются. '
          'При полной замене текущая база будет заменена содержимым файла.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Полная замена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Объединить'),
          ),
        ],
      ),
    );
    if (merge == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await BackupService.instance.importFromFiles(merge: merge);
      if (!mounted) return;
      if (result == BackupImportResult.imported) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(merge
              ? 'Данные объединены. Существующие записи сохранены.'
              : 'Данные успешно восстановлены.'),
        ));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось восстановить данные: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Настройки', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 20),
      SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Резервное копирование', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 8),
          const Text(
            'Создайте файл со всей сохранённой историей сна, оценками, тегами и заметками. '
            'Файл можно сохранить в «Файлы» или перенести на другой iPhone.',
            style: TextStyle(color: AppTheme.muted, height: 1.5),
          ),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _busy ? null : _createBackup,
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Создать резервную копию'),
          )),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: _busy ? null : _restoreBackup,
            icon: const Icon(Icons.restore),
            label: const Text('Восстановить из файла'),
          )),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 8),
          const Text(
            'Восстановление заменяет текущую локальную базу. Сначала сохраните её копию.',
            style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
          ),
        ],
      )),
      const SizedBox(height: 12),
      SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Apple Health и Apple Watch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 8),
          const Text(
            'Импорт доступных интервалов сна за последние 30 дней. Доступ зависит от разрешений iOS и данных, которые действительно записаны в Apple Health. Отсутствующие фазы не восстанавливаются догадками.',
            style: TextStyle(color: AppTheme.muted, height: 1.5),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: _busy ? null : _syncAppleHealth,
            icon: const Icon(Icons.favorite_outline),
            label: const Text('Импортировать данные сна'),
          )),
          const SizedBox(height: 8),
          const Text('Синхронизация доступна вручную. Повторный импорт не создаёт дубликаты ранее добавленных ночей.',
            style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
        ],
      )),
      const SizedBox(height: 12),
      SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Аудиособытия', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 8),
        const Text('Микрофон анализирует уровень звука во время включённого наблюдения; в файл сохраняются только отдельные фрагменты вокруг обнаруженных звуковых событий, а не вся ночь. Для ночной работы приложение должно быть запущено и получить разрешение микрофона. iOS может прервать фоновый захват — это обязательно проверим на iPhone. После записи событие классифицируется встроенной моделью Apple SoundAnalysis. Если уверенность недостаточна или метка не сопоставлена, остаётся «Неопределённый звук»; категорию можно исправить вручную.', style: TextStyle(color: AppTheme.muted, height: 1.45)),
        const SizedBox(height: 12),
        ValueListenableBuilder<bool>(valueListenable: AudioObservationService.instance.observing, builder: (context, recording, _) => Column(children: [
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _busy ? null : (recording ? _stopAudioClip : _startAudioClip),
            icon: Icon(recording ? Icons.stop_circle_outlined : Icons.mic_none),
            label: Text(recording ? 'Остановить аудионаблюдение' : 'Начать аудионаблюдение'),
          )),
          if (recording) ValueListenableBuilder<bool>(valueListenable: AudioObservationService.instance.paused, builder: (context, paused, _) => OutlinedButton.icon(
            onPressed: _busy ? null : () async { if (paused) { await AudioObservationService.instance.resumeObservation(); } else { await AudioObservationService.instance.pauseObservation(); } },
            icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            label: Text(paused ? 'Возобновить наблюдение' : 'Пауза'),
          )),
          if (recording) const Padding(padding: EdgeInsets.only(top: 10), child: Text('Аудионаблюдение активно. Сохраняются только обнаруженные звуковые события.', style: TextStyle(color: AppTheme.teal))),
        ])),
      ])),
      const SizedBox(height: 12),
      const AudioEventsPanel(),
      const SizedBox(height: 12),
      SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Отчёты и очистка аудио', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 8),
        const Text('Аудиофайлы хранятся не более 7 дней. При запуске приложения просроченные файлы и их записи удаляются; история сна и отчёты остаются.', style: TextStyle(color: AppTheme.muted, height: 1.45)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: _busy ? null : () => _run(() => PdfReportService.exportHistory(days: 7), 'Недельный PDF-отчёт подготовлен.'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('7 дней')),
          OutlinedButton.icon(onPressed: _busy ? null : () => _run(() => PdfReportService.exportHistory(days: 30), 'Месячный PDF-отчёт подготовлен.'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('30 дней')),
          OutlinedButton.icon(onPressed: _busy ? null : () => _run(() => PdfReportService.exportHistory(days: 3650), 'Отчёт за весь период подготовлен.'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Весь период')),
        ]),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          onPressed: _busy ? null : () => _run(() async { await SleepDatabase.instance.deleteExpiredAudioEvents(DateTime.now()); final events = await SleepDatabase.instance.getAudioEvents(); await NotificationService.instance.scheduleAudioExpiry(events.map((row) => DateTime.parse(row['expires_at']! as String))); }, 'Проверка срока хранения завершена.'),
          icon: const Icon(Icons.cleaning_services_outlined), label: const Text('Удалить просроченные аудиофайлы'),
        )),
      ])),
    ],
  );
}



class AudioEventsPanel extends StatefulWidget {
  const AudioEventsPanel({super.key});
  @override
  State<AudioEventsPanel> createState() => _AudioEventsPanelState();
}

class _AudioEventsPanelState extends State<AudioEventsPanel> {
  final AudioPlayer _player = AudioPlayer();
  Future<List<Map<String, Object?>>> _load() => SleepDatabase.instance.getAudioEvents();
  static const categories = <String, String>{
    'unknown': 'Неопределённый звук', 'snore': 'Храп', 'cough': 'Кашель',
    'speech': 'Разговор', 'laugh': 'Смех', 'groan': 'Стон', 'noise': 'Посторонний шум',
  };
  @override
  void dispose() { _player.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => SectionCard(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Сохранённые аудиофрагменты', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
      const SizedBox(height: 8),
      FutureBuilder<List<Map<String, Object?>>>(future: _load(), builder: (context, snapshot) {
        if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
        final events = snapshot.data!;
        if (events.isEmpty) return const Text('Пока нет сохранённых аудиособытий.', style: TextStyle(color: AppTheme.muted));
        return Column(children: events.map((event) {
          final id = event['id']! as String;
          final path = event['file_path']! as String;
          final category = event['category'] as String? ?? 'unknown';
          final captured = DateTime.tryParse(event['captured_at'] as String? ?? '')?.toLocal();
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: IconButton(icon: const Icon(Icons.play_circle_outline), onPressed: () async {
              if (await File(path).exists()) await _player.play(DeviceFileSource(path));
              else if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Аудиофайл не найден.')));
            }),
            title: Text(categories[category] ?? categories['unknown']!),
            subtitle: Text('${captured == null ? 'Дата неизвестна' : '${captured.day.toString().padLeft(2,'0')}.${captured.month.toString().padLeft(2,'0')}.${captured.year} ${captured.hour.toString().padLeft(2,'0')}:${captured.minute.toString().padLeft(2,'0')}'} · хранение 7 дней${event['user_corrected'] == 1 ? ' · исправлено вручную' : event['confidence'] == null ? '' : ' · уверенность ${((event['confidence'] as num).toDouble() * 100).round()}%'}'),
            trailing: PopupMenuButton<String>(onSelected: (value) async {
              if (value == 'delete') { await SleepDatabase.instance.deleteAudioEvent(id); final remaining = await SleepDatabase.instance.getAudioEvents(); await NotificationService.instance.scheduleAudioExpiry(remaining.map((row) => DateTime.parse(row['expires_at']! as String))); }
              else { await SleepDatabase.instance.updateAudioCategory(id, value); }
              if (mounted) setState(() {});
            }, itemBuilder: (_) => [
              ...categories.entries.map((entry) => PopupMenuItem(value: entry.key, child: Text('Категория: ${entry.value}'))),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Text('Удалить фрагмент')),
            ]),
            isThreeLine: false,
          );
        }).toList());
      }),
    ],
  ));
}
