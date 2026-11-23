import 'dart:async';
import 'package:flutter/material.dart';
import '../data/storage_service.dart';
import '../features/settings/storage_management_panel.dart';

class StorageWarningBanner extends StatefulWidget {
  const StorageWarningBanner({super.key});

  @override
  State<StorageWarningBanner> createState() => _StorageWarningBannerState();
}

class _StorageWarningBannerState extends State<StorageWarningBanner> with WidgetsBindingObserver {
  Timer? _timer;
  int? _freeBytes;
  int _threshold = StorageService.defaultWarningThreshold;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final snapshot = await StorageService.instance.measure();
      final threshold = await StorageService.instance.getWarningThreshold();
      if (!mounted) return;
      setState(() {
        _freeBytes = snapshot.freeBytes;
        _threshold = threshold;
      });
    } catch (_) {
      if (mounted) setState(() => _freeBytes = null);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _format(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} МБ';
  }

  @override
  Widget build(BuildContext context) {
    final free = _freeBytes;
    if (free == null || free >= _threshold) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF5A3D24).withValues(alpha: .35),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE6BC70).withValues(alpha: .55)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFE6BC70)),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'На iPhone осталось ${_format(free)} свободного места — ниже выбранного порога ${_format(_threshold)}. Приложение не удаляет ваши данные автоматически.',
                style: const TextStyle(height: 1.4, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const StorageManagementScreen(),
                  )),
                  child: const Text('Открыть управление хранилищем'),
                ),
              ),
            ],
          )),
        ]),
      ),
    );
  }
}
