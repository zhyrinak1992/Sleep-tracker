import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/sleep_database.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

/// Audio clips belonging to one recorded sleep session.
class SleepNightAudioCard extends StatefulWidget {
  const SleepNightAudioCard({
    super.key,
    required this.database,
    required this.sessionId,
  });

  final SleepDatabase database;
  final String sessionId;

  @override
  State<SleepNightAudioCard> createState() => _SleepNightAudioCardState();
}

class _SleepNightAudioCardState extends State<SleepNightAudioCard> {
  final AudioPlayer _player = AudioPlayer();
  late Future<List<Map<String, Object?>>> _eventsFuture;

  static const _categories = <String, String>{
    'unknown': 'Неопределённый звук',
    'snore': 'Храп',
    'cough': 'Кашель',
    'speech': 'Разговор',
    'laugh': 'Смех',
    'groan': 'Стон',
    'sobbing': 'Всхлипывания',
    'noise': 'Посторонний шум',
  };

  @override
  void initState() {
    super.initState();
    _eventsFuture = widget.database.getAudioEvents(sessionId: widget.sessionId);
  }

  @override
  void didUpdateWidget(covariant SleepNightAudioCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.database != widget.database ||
        oldWidget.sessionId != widget.sessionId) {
      _eventsFuture = widget.database.getAudioEvents(sessionId: widget.sessionId);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _duration(Object? raw) {
    if (raw is! num || raw <= 0) return 'Длительность не указана';
    final seconds = (raw / 1000).round();
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return minutes == 0 ? '$remainder с' : '$minutes мин ${remainder.toString().padLeft(2, '0')} с';
  }

  Future<void> _play(String path) async {
    if (!await File(path).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Аудиофайл больше недоступен.')),
        );
      }
      return;
    }
    await _player.stop();
    await _player.play(DeviceFileSource(path));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, Object?>>>(
    future: _eventsFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const SectionCard(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Звуки этой ночи', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            LinearProgressIndicator(),
          ],
        ));
      }
      if (snapshot.hasError) {
        return const SectionCard(child: Text('Не удалось загрузить звуки этой ночи.'));
      }
      final events = snapshot.data ?? const <Map<String, Object?>>[];
      return SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Звуки этой ночи', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          if (events.isEmpty)
            const Text(
              'Для этой ночи сохранённых звуковых событий нет.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12),
            )
          else
            for (final event in events) ...[
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: IconButton(
                  tooltip: event['file_path'] is String ? 'Воспроизвести фрагмент' : 'Файл больше не хранится',
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  onPressed: event['file_path'] is String && (event['file_path'] as String).isNotEmpty
                      ? () => _play(event['file_path']! as String)
                      : null,
                ),
                title: Text(
                  _categories[event['category'] as String? ?? 'unknown'] ??
                      'Неопределённый звук',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                subtitle: Text(
                  '${DateFormat('HH:mm').format(DateTime.parse(event['captured_at']! as String).toLocal())} · ${_duration(event['duration_ms'])} · ${event['file_path'] is String ? 'файл доступен' : 'файл удалён после 7 дней'}',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
                dense: true,
              ),
            ],
        ],
      ));
    },
  );
}
