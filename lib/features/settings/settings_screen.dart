import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:io';

import '../../data/backup_service.dart';
import '../../data/comparison_suggestion_store.dart';
import '../../data/app_lock_service.dart';
import '../../data/apple_health_service.dart';
import '../../data/apple_health_file_import_service.dart';
import '../../data/audio_observation_service.dart';
import '../../data/pdf_report_service.dart';
import '../../data/sleep_database.dart';
import 'storage_management_panel.dart';
import '../../data/notification_service.dart';
import '../../data/yandex_smart_home_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import '../../widgets/screen_header.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  bool _healthConnected = false;
  YandexHomeSnapshot? _yandexHome;
  String? _selectedYandexDeviceId;
  bool _yandexConnected = false;
  ComparisonSuggestionFrequency? _comparisonFrequency;
  bool _savingComparisonFrequency = false;

  @override
  void initState() {
    super.initState();
    _loadHealthOnboarding();
    _loadYandexConnection();
    _loadComparisonSuggestionFrequency();
  }



  Future<void> _loadComparisonSuggestionFrequency() async {
    final frequency = await ComparisonSuggestionStore(
      SleepDatabase.instance.getAppMetadata,
      SleepDatabase.instance.setAppMetadata,
    ).loadFrequency();
    if (mounted) setState(() => _comparisonFrequency = frequency);
  }

  Future<void> _saveComparisonSuggestionFrequency(ComparisonSuggestionFrequency frequency) async {
    if (_savingComparisonFrequency) return;
    setState(() => _savingComparisonFrequency = true);
    try {
      await ComparisonSuggestionStore(
        SleepDatabase.instance.getAppMetadata,
        SleepDatabase.instance.setAppMetadata,
      ).saveFrequency(frequency);
      if (mounted) setState(() => _comparisonFrequency = frequency);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить частоту предложений: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingComparisonFrequency = false);
    }
  }

  Future<void> _loadYandexConnection() async {
    final service = YandexSmartHomeService.instance;
    final connected = await service.isConnected;
    final selected = await SleepDatabase.instance.getAppMetadata('yandex_selected_device_id');
    if (!mounted) return;
    setState(() { _yandexConnected = connected; _selectedYandexDeviceId = selected; });
    if (connected) await _loadYandexHome();
  }

  Future<void> _connectYandex() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final service = YandexSmartHomeService.instance;
      final authorization = await service.requestDeviceAuthorization();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Подтверждение в Яндексе'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Откройте страницу Яндекса, войдите в нужный аккаунт и разрешите Sleep Tracker доступ к данным умного дома.'),
              const SizedBox(height: 16),
              SelectableText(
                authorization.userCode,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 3),
              ),
              const SizedBox(height: 8),
              const Text('Код действует ограниченное время. После подтверждения вернитесь сюда.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            OutlinedButton(
              onPressed: () => launchUrl(
                Uri.parse(authorization.verificationUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Открыть Яндекс'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Я подтвердил'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await service.completeDeviceAuthorization(authorization);
      final home = await service.fetchHome();
      final previous = await SleepDatabase.instance.getAppMetadata('yandex_selected_device_id');
      if (!mounted) return;
      setState(() {
        _yandexHome = home;
        _yandexConnected = true;
        _selectedYandexDeviceId = home.devices.any((d) => d.id == previous) ? previous : null;
      });
      await SleepDatabase.instance.setAppMetadata('yandex_connected', 'true');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Яндекс подключён. Датчиков с температурой или влажностью: ${home.devices.length}.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось подключить Яндекс: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadYandexHome() async {
    try {
      final home = await YandexSmartHomeService.instance.fetchHome();
      final previous = _selectedYandexDeviceId ?? await SleepDatabase.instance.getAppMetadata('yandex_selected_device_id');
      if (!mounted) return;
      setState(() {
        _yandexHome = home; _yandexConnected = true;
        _selectedYandexDeviceId = home.devices.any((d) => d.id == previous) ? previous : null;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось обновить список устройств Яндекса: $error')));
    }
  }

  Future<void> _refreshYandexSensor() async {
    final deviceId = _selectedYandexDeviceId;
    if (deviceId == null) return;
    setState(() => _busy = true);
    try {
      final activeSession = await SleepDatabase.instance.getOpenSession();
      final count = await YandexSmartHomeService.instance.refreshSelectedDevice(deviceId: deviceId, sessionId: activeSession?.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(count == 0
        ? 'Новых измерений нет: датчик не передал обновлённые значения температуры или влажности.'
        : 'Получено и сохранено новых измерений: $count.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось получить показания датчика: $error')));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _disconnectYandex() async {
    await YandexSmartHomeService.instance.disconnect();
    await SleepDatabase.instance.setAppMetadata('yandex_connected', 'false');
    await SleepDatabase.instance.setAppMetadata('yandex_selected_device_id', '');
    if (!mounted) return;
    setState(() { _yandexConnected = false; _yandexHome = null; _selectedYandexDeviceId = null; });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _changeAppLock(bool value) async {
    final service = AppLockService.instance;
    if (value) {
      if (!await service.isAvailable()) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('На устройстве не обнаружена поддержка системной биометрии или блокировки кодом.')),
        );
        return;
      }
      await service.setEnabled(true);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Защита включена. При возвращении в приложение потребуется подтверждение личности.')),
      );
      return;
    }
    final confirmed = await service.authenticate(reason: 'Подтвердите отключение защиты Sleep Tracker');
    if (!confirmed) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Отключение отменено. Защита осталась включённой.')),
      );
      return;
    }
    await service.setEnabled(false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Защита приложения отключена.')),
    );
  }

  Future<void> _loadHealthOnboarding() async {
    final db = SleepDatabase.instance;
    final connected = await db.getAppMetadata('apple_health_connected') == 'true';
    final shown = await db.getAppMetadata('apple_health_intro_shown') == 'true';
    if (!mounted) return;
    setState(() => _healthConnected = connected);
    if (!shown) {
      await db.setAppMetadata('apple_health_intro_shown', 'true');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Подключить Apple Health?'),
          content: const Text('Можно импортировать интервалы сна, физиологические показатели и доступную дневную активность: шаги, активную энергию, минуты упражнений и тренировки. Sleep Tracker запрашивает только чтение — данные в Apple Health не изменяются.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Позже')),
            FilledButton(onPressed: () { Navigator.pop(ctx); _syncAppleHealth(); }, child: const Text('Подключить')),
          ],
        ));
      });
    }
  }

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
      await SleepDatabase.instance.setAppMetadata('apple_health_connected', 'true');
      if (!mounted) return;
      setState(() => _healthConnected = true);
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


  Future<void> _importAppleHealthFile() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final preview = await AppleHealthFileImportService.instance.chooseAndPreview();
      if (!mounted || preview == null) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Проверка данных Apple Health'),
          content: Text(
            'Найдено в архиве:\\n'
            '• ночей сна: ${preview.nights}\\n'
            '• интервалов фаз: ${preview.stages}\\n'
            '• измерений здоровья: ${preview.metrics}\\n\\n'
            'Данные будут добавлены в общую историю приложения. Уже импортированные записи не создадут дубликаты.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Импортировать')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final result = await preview.importIntoDatabase();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Импорт завершён: новых ночей — ${result.nights}, фаз — ${result.stages}, измерений — ${result.metrics}.'),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось импортировать архив Apple Health: $error')),
      );
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

  Future<String?> _requestBackupPassword({required bool confirm}) async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    String? errorText;
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(confirm ? 'Задать пароль копии' : 'Пароль резервной копии'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Пароль не сохраняется в приложении. Он понадобится при восстановлении на этом или другом iPhone. Используйте не менее 10 символов.'),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: 'Пароль', border: OutlineInputBorder()),
                ),
                if (confirm) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'Повторите пароль', border: OutlineInputBorder()),
                  ),
                ],
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(errorText!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () {
                  final password = passwordController.text;
                  if (password.length < 10) {
                    setDialogState(() => errorText = 'Нужно не менее 10 символов.');
                    return;
                  }
                  if (confirm && password != confirmController.text) {
                    setDialogState(() => errorText = 'Пароли не совпадают.');
                    return;
                  }
                  Navigator.pop(dialogContext, password);
                },
                child: Text(confirm ? 'Создать копию' : 'Продолжить'),
              ),
            ],
          ),
        ),
      );
    } finally {
      passwordController.dispose();
      confirmController.dispose();
    }
  }

  Future<void> _createBackup() async {
    final password = await _requestBackupPassword(confirm: true);
    if (password == null || !mounted) return;
    await _run(
      () => BackupService.instance.exportToFiles(password: password),
      'Зашифрованная резервная копия подготовлена. Выберите «Сохранить в Файлы».',
    );
  }

  Future<void> _restoreBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final draft = await BackupService.instance.prepareImportFromFiles(
        requestPassword: () => _requestBackupPassword(confirm: false),
      );
      if (draft == null || !mounted) return;
      final preview = draft.preview;
      final date = preview.createdAt == null
          ? 'не указана'
          : MaterialLocalizations.of(context).formatMediumDate(preview.createdAt!.toLocal());
      final merge = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Содержимое резервной копии'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Дата создания: $date'),
                Text('Версия архива: ${preview.formatVersion}'),
                const SizedBox(height: 12),
                _backupPreviewRow('Ночи сна', preview.sessions),
                _backupPreviewRow('Утренние отчёты', preview.reports),
                _backupPreviewRow('Заметки', preview.notes),
                _backupPreviewRow('Аудиособытия', preview.audioEvents),
                _backupPreviewRow('Аудиофайлы в архиве', preview.audioFiles),
                _backupPreviewRow('Этапы сна', preview.stages),
                _backupPreviewRow('Физиологические показатели', preview.metrics),
                _backupPreviewRow('Измерения микроклимата', preview.climateSamples),
                _backupPreviewRow('Теги', preview.tags),
                _backupPreviewRow('Исторические снимки главных изменений', preview.changeHistorySnapshots),
                const SizedBox(height: 12),
                const Text('Архив проверен. До выбора действия текущие данные не изменялись.'),
                const SizedBox(height: 8),
                const Text('Полная замена удалит текущие данные приложения и заменит их содержимым архива. Объединение сохранит существующие записи и добавит отсутствующие.'),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
            OutlinedButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Полная замена')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Объединить')),
          ],
        ),
      );
      if (merge == null || !mounted) return;
      final result = await BackupService.instance.restorePreparedBackup(draft: draft, merge: merge);
      if (!mounted) return;
      if (result == BackupImportResult.imported) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(merge ? 'Данные объединены. Существующие записи сохранены.' : 'Данные успешно восстановлены.'),
        ));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось восстановить данные: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _backupPreviewRow(String label, int count) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [Expanded(child: Text(label)), Text('$count', style: const TextStyle(fontWeight: FontWeight.w600))]),
  );

  Future<void> _exportCustomReport() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDateRange: DateTimeRange(
        start: today.subtract(const Duration(days: 29)),
        end: today,
      ),
      helpText: 'Выберите период отчёта',
      saveText: 'Подготовить PDF',
      cancelText: 'Отмена',
      confirmText: 'Продолжить',
    );
    if (range == null || !mounted) return;
    await _run(
      () => PdfReportService.exportHistory(from: range.start, to: range.end),
      'PDF-отчёт за выбранный период подготовлен.',
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const ScreenHeader(
        title: 'Настройки',
        subtitle: 'Безопасность, источники данных и резервные копии',
        icon: Icons.tune_rounded,
      ),
      const SizedBox(height: 0),
      SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Предложения сравнений', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 6),
          const Text('На главном экране одновременно появляется не более одной карточки. Повторные предложения требуют новых наблюдений или заметного обновления результата; отдельные push-уведомления не отправляются.',
            style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45)),
          const SizedBox(height: 10),
          if (_comparisonFrequency == null)
            const LinearProgressIndicator()
          else
            DropdownButtonFormField<ComparisonSuggestionFrequency>(
              key: ValueKey(_comparisonFrequency),
              initialValue: _comparisonFrequency,
              decoration: const InputDecoration(labelText: 'Частота показа'),
              items: ComparisonSuggestionFrequency.values.map((frequency) => DropdownMenuItem(
                value: frequency,
                child: Text('${frequency.label} — ${frequency.description}'),
              )).toList(),
              onChanged: _savingComparisonFrequency ? null : (value) {
                if (value != null) _saveComparisonSuggestionFrequency(value);
              },
            ),
          if (_savingComparisonFrequency)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
        ],
      )),
      const SizedBox(height: 12),
      SectionCard(child: ValueListenableBuilder<bool>(
        valueListenable: AppLockService.instance.enabled,
        builder: (context, enabled, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Защита приложения', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 8),
          const Text('Используется системная биометрия Face ID / Touch ID или код-пароль устройства. При сворачивании приложения экран блокируется; при следующем открытии потребуется подтверждение. Биометрические данные не сохраняются в Sleep Tracker.', style: TextStyle(color: AppTheme.muted, height: 1.45)),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Блокировать приложение'),
            subtitle: Text(enabled ? 'Защита включена' : 'Защита выключена'),
            value: enabled,
            onChanged: _busy ? null : _changeAppLock,
          ),
        ]),
      )),
      const SizedBox(height: 12),
      SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Резервное копирование', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 8),
          const Text(
            'Резервная копия содержит историю сна, оценки, теги, заметки, показатели, настройки и сохранённые аудиофрагменты. Новый формат шифруется паролем AES-256-GCM и подходит для переноса на другой iPhone.',
            style: TextStyle(color: AppTheme.muted, height: 1.5),
          ),
          const SizedBox(height: 8),
          const Text(
            'Запомните пароль: приложение не хранит его и не сможет восстановить. Старые незашифрованные JSON-копии также можно импортировать, но при переносе рекомендуется создать новую зашифрованную копию.',
            style: TextStyle(color: AppTheme.teal, fontSize: 12, height: 1.45),
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
            'Перед восстановлением выберите режим: «Объединить» сохранит текущие записи и добавит отсутствующие; «Полная замена» заменит локальную историю данными из архива. Перед полной заменой рекомендуется создать отдельную резервную копию текущих данных.',
            style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
          ),
        ],
      )),
      const SizedBox(height: 12),
      const StorageManagementPanel(),
      const SizedBox(height: 12),
      SectionCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Text('Apple Health и Apple Watch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
            Icon(_healthConnected ? Icons.check_circle : Icons.link, color: _healthConnected ? AppTheme.teal : AppTheme.muted),
          ]),
          const SizedBox(height: 8),
          const Text(
            'Подключите Apple Health, чтобы импортировать интервалы сна, физиологические показатели и дневную активность за последние 30 дней. Доступные шаги, активная энергия, минуты упражнений и тренировки сопоставляются с предшествующим ночи периодом бодрствования. Приложение запрашивает только чтение. Набор данных зависит от разрешений iOS и фактических записей в Apple Health; отсутствующие значения не подставляются.',
            style: TextStyle(color: AppTheme.muted, height: 1.5),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: _busy ? null : _syncAppleHealth,
            icon: const Icon(Icons.favorite_outline),
            label: Text(_healthConnected ? 'Синхронизировать сон и активность' : 'Подключить Apple Health и синхронизировать'),
          )),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _busy ? null : _importAppleHealthFile,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Импортировать из файла Apple Health'),
          )),
          const SizedBox(height: 8),
          const Text('Выберите ZIP-архив, экспортированный из приложения «Здоровье». Перед сохранением приложение покажет найденные записи.',
            style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
          const SizedBox(height: 8),
          Text(_healthConnected ? 'Apple Health подключён. Синхронизацию можно запускать вручную; повторный импорт не создаёт дубликаты ранее добавленных ночей.' : 'Подключение выполняется только после вашего нажатия. Разрешение можно изменить в настройках iOS.',
            style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
        ],
      )),
      const SizedBox(height: 12),

      SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Яндекс Умный дом — климат спальни', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
          Icon(_yandexConnected ? Icons.check_circle : Icons.home_outlined, color: _yandexConnected ? AppTheme.teal : AppTheme.muted),
        ]),
        const SizedBox(height: 8),
        const Text('Подключение через подтверждение в Яндексе. Sleep Tracker получает только доступные значения температуры и влажности, сохраняет измерения локально и не управляет устройствами. Запрашивается исключительно разрешение iot:view; iot:control не используется.',
          style: TextStyle(color: AppTheme.muted, height: 1.45)),
        const SizedBox(height: 12),
        if (!_yandexConnected) ...[
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _connectYandex,
            icon: const Icon(Icons.link), label: Text(_busy ? 'Ожидание подтверждения…' : 'Подключить аккаунт Яндекса'))),
          const SizedBox(height: 6),
          const Text('Токен доступа и токен обновления хранятся в iOS Keychain и не включаются в резервную копию.',
            style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
        ] else ...[
          Row(children: [
            Expanded(child: Text('Найдено датчиков: ${_yandexHome?.devices.length ?? 0}')),
            IconButton(onPressed: _busy ? null : _loadYandexHome, icon: const Icon(Icons.refresh), tooltip: 'Обновить список'),
          ]),
          if ((_yandexHome?.devices.isEmpty ?? true))
            const Text('Яндекс не вернул датчики с доступными для чтения температурой или влажностью.', style: TextStyle(color: AppTheme.muted)),
          ...?_yandexHome?.devices.map((device) => RadioListTile<String>(
            contentPadding: EdgeInsets.zero, value: device.id, groupValue: _selectedYandexDeviceId,
            onChanged: _busy ? null : (value) async {
              setState(() => _selectedYandexDeviceId = value);
              await SleepDatabase.instance.setAppMetadata('yandex_selected_device_id', value ?? '');
            },
            title: Text(device.name),
            subtitle: Text('${device.roomName ?? 'Комната не указана'} · ${device.online ? 'в сети' : 'не в сети'} · ${[if (device.hasTemperature) 'температура', if (device.hasHumidity) 'влажность'].join(', ')}'),
          )),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy || _selectedYandexDeviceId == null ? null : _refreshYandexSensor,
            icon: const Icon(Icons.thermostat), label: const Text('Получить актуальные показания'))),
          SizedBox(width: double.infinity, child: TextButton.icon(onPressed: _busy ? null : _disconnectYandex,
            icon: const Icon(Icons.link_off), label: const Text('Отключить Яндекс'))),
        ],
      ])),
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
          OutlinedButton.icon(onPressed: _busy ? null : () => _run(() => PdfReportService.exportHistory(days: 7), 'Недельный PDF-отчёт подготовлен.'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Неделя')),
          OutlinedButton.icon(onPressed: _busy ? null : () => _run(() => PdfReportService.exportHistory(days: 30), 'Месячный PDF-отчёт подготовлен.'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Месяц')),
          OutlinedButton.icon(onPressed: _busy ? null : () => _run(() => PdfReportService.exportHistory(days: 90), 'PDF-отчёт за квартал подготовлен.'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Квартал')),
          OutlinedButton.icon(onPressed: _busy ? null : () => _run(() => PdfReportService.exportHistory(days: 180), 'PDF-отчёт за полгода подготовлен.'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Полгода')),
          OutlinedButton.icon(onPressed: _busy ? null : () => _run(() => PdfReportService.exportHistory(days: 365), 'Годовой PDF-отчёт подготовлен.'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Год')),
          OutlinedButton.icon(onPressed: _busy ? null : () => _run(() => PdfReportService.exportHistory(days: 3650), 'Отчёт за весь период подготовлен.'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Вся история')),
          OutlinedButton.icon(onPressed: _busy ? null : _exportCustomReport, icon: const Icon(Icons.date_range_outlined), label: const Text('Произвольный период')),
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
