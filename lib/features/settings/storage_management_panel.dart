import 'package:flutter/material.dart';
import '../../data/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class StorageManagementPanel extends StatefulWidget {
  const StorageManagementPanel({super.key});

  @override
  State<StorageManagementPanel> createState() => _StorageManagementPanelState();
}

class _StorageManagementPanelState extends State<StorageManagementPanel> {
  late Future<StorageSnapshot> _snapshot;
  int _threshold = StorageService.defaultWarningThreshold;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _snapshot = StorageService.instance.measure();
    _loadThreshold();
  }

  Future<void> _loadThreshold() async {
    final value = await StorageService.instance.getWarningThreshold();
    if (mounted) setState(() => _threshold = value);
  }

  Future<void> _reload() async {
    setState(() => _snapshot = StorageService.instance.measure());
    await _snapshot;
    await _loadThreshold();
  }

  String _formatBytes(int? bytes) {
    if (bytes == null) return 'Недоступно';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()} КБ';
    return '$bytes Б';
  }

  Future<void> _changeThreshold(int value) async {
    await StorageService.instance.setWarningThreshold(value);
    if (mounted) setState(() => _threshold = value);
  }

  Future<void> _clearCache(StorageSnapshot snapshot) async {
    if (snapshot.cacheBytes == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Кэш приложения уже пуст.')),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить кэш приложения?'),
        content: Text(
          'Будет удалено содержимое кэша объёмом примерно ${_formatBytes(snapshot.cacheBytes)}. '
          'История сна, заметки, аудиофрагменты, PDF-отчёты и резервные копии не затрагиваются.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Очистить кэш')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      final removed = await StorageService.instance.clearCache();
      await _reload();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Очищено: ${_formatBytes(removed)}')),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось очистить кэш: $error')),
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Widget _sizeRow(String label, int bytes) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted))),
      Text(_formatBytes(bytes), style: const TextStyle(fontWeight: FontWeight.w600)),
    ]),
  );

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Expanded(child: Text('Хранилище iPhone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
          IconButton(
            tooltip: 'Обновить сведения',
            onPressed: _clearing ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ]),
        const SizedBox(height: 4),
        const Text(
          'Показывается размер файлов Sleep Tracker в контейнере приложения. Данные других приложений не учитываются.',
          style: TextStyle(color: AppTheme.muted, height: 1.4, fontSize: 12),
        ),
        const SizedBox(height: 10),
        FutureBuilder<StorageSnapshot>(
          future: _snapshot,
          builder: (context, state) {
            if (state.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (state.hasError || !state.hasData) {
              return Text(
                'Не удалось измерить использование памяти: ${state.error ?? 'нет данных'}.',
                style: const TextStyle(color: AppTheme.muted),
              );
            }
            final data = state.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Занято приложением: ${_formatBytes(data.appBytes)}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(
                  data.freeBytes == null
                      ? 'Свободное место iPhone: iOS не предоставила точное значение.'
                      : 'Свободно на iPhone: ${_formatBytes(data.freeBytes)} из ${_formatBytes(data.totalDiskBytes)}',
                  style: const TextStyle(color: AppTheme.muted),
                ),
                if (data.freeBytes != null && data.freeBytes! < _threshold) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5A3D24).withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE6BC70).withValues(alpha: 0.55)),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFE6BC70)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        'На iPhone осталось меньше ${_formatBytes(_threshold)}. Проверьте хранилище и при необходимости очистите кэш. Пользовательские данные автоматически не удаляются.',
                        style: const TextStyle(height: 1.4),
                      )),
                    ]),
                  ),
                ],
                const SizedBox(height: 12),
                _sizeRow('База сна, заметки и показатели', data.databaseBytes),
                _sizeRow('Аудиофрагменты', data.audioBytes),
                _sizeRow('PDF-отчёты во временном хранилище', data.reportBytes),
                _sizeRow('Резервные копии во временном хранилище', data.backupBytes),
                _sizeRow('Кэш приложения', data.cacheBytes),
                _sizeRow('Прочие файлы приложения', data.otherBytes),
                const Divider(height: 22),
                const Text('Порог предупреждения', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButton<int>(
                  value: _threshold,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 500 * 1024 * 1024, child: Text('500 МБ')),
                    DropdownMenuItem(value: 1024 * 1024 * 1024, child: Text('1 ГБ')),
                    DropdownMenuItem(value: 2 * 1024 * 1024 * 1024, child: Text('2 ГБ')),
                  ],
                  onChanged: _clearing ? null : (value) { if (value != null) _changeThreshold(value); },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _clearing ? null : () => _clearCache(data),
                    icon: _clearing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cleaning_services_outlined),
                    label: Text(_clearing ? 'Очистка…' : 'Очистить кэш'),
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Очистка затрагивает только системную папку Caches. История сна, аудио, отчёты и резервные копии не удаляются.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
