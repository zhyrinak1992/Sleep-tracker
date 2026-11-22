import 'package:flutter/material.dart';
import '../../data/app_lock_service.dart';
import '../../theme/app_theme.dart';

class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _authenticating = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLockService.instance.enabled.addListener(_onSettingChanged);
    _initialize();
  }

  Future<void> _initialize() async {
    await AppLockService.instance.initialize();
    if (!mounted) return;
    setState(() => _initialized = true);
    if (AppLockService.instance.enabled.value) await _unlock();
    else if (mounted) setState(() => _unlocked = true);
  }

  void _onSettingChanged() {
    if (!mounted) return;
    if (AppLockService.instance.enabled.value) {
      setState(() => _unlocked = false);
      _unlock();
    } else {
      setState(() => _unlocked = true);
    }
  }

  Future<void> _unlock() async {
    if (_authenticating || !AppLockService.instance.enabled.value) return;
    _authenticating = true;
    final success = await AppLockService.instance.authenticate();
    _authenticating = false;
    if (!mounted) return;
    setState(() => _unlocked = success);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!AppLockService.instance.enabled.value || !_initialized) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!_authenticating) setState(() => _unlocked = false);
    } else if (state == AppLifecycleState.resumed && !_unlocked) {
      _unlock();
    }
  }

  @override
  void dispose() {
    AppLockService.instance.enabled.removeListener(_onSettingChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_unlocked || !AppLockService.instance.enabled.value) return widget.child;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 58, color: AppTheme.teal),
                const SizedBox(height: 18),
                const Text('Sleep Tracker заблокирован',
                  style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Подтвердите личность, чтобы открыть дневник сна и личные данные.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.muted, height: 1.45)),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _authenticating ? null : _unlock,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Разблокировать'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
