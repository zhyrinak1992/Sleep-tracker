import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../data/app_lock_service.dart';
import '../../theme/app_theme.dart';
import 'app_lock_policy.dart';

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
  bool _obscured = false;
  DateTime? _backgroundedAt;
  Timer? _idleTimer;

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
    if (AppLockService.instance.enabled.value) {
      await _unlock();
    } else {
      setState(() => _unlocked = true);
    }
  }

  void _onSettingChanged() {
    if (!mounted) return;
    if (AppLockService.instance.enabled.value) {
      _idleTimer?.cancel();
      setState(() => _unlocked = false);
      _unlock();
    } else {
      _idleTimer?.cancel();
      setState(() {
        _unlocked = true;
        _obscured = false;
      });
    }
  }

  void _armIdleTimer() {
    _idleTimer?.cancel();
    if (!mounted || !_unlocked || _obscured ||
        !AppLockService.instance.enabled.value || _authenticating) {
      return;
    }
    _idleTimer = Timer(appLockIdleTimeout, () {
      if (!mounted || !AppLockService.instance.enabled.value) return;
      setState(() => _unlocked = false);
      _unlock();
    });
  }

  void _onUserActivity(PointerDownEvent event) {
    _armIdleTimer();
  }

  Future<void> _unlock() async {
    if (_authenticating || !AppLockService.instance.enabled.value) return;
    _authenticating = true;
    _idleTimer?.cancel();
    final success = await AppLockService.instance.authenticate();
    _authenticating = false;
    if (!mounted) return;
    setState(() {
      _unlocked = success;
      _obscured = false;
    });
    if (success) _armIdleTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!AppLockService.instance.enabled.value || !_initialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_authenticating) return;
      _idleTimer?.cancel();
      _backgroundedAt ??= DateTime.now();
      // Hide personal information in the app switcher without prematurely
      // requiring authentication if the user returns within 60 seconds.
      if (_unlocked && mounted) setState(() => _obscured = true);
      return;
    }

    if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      final elapsed = backgroundedAt == null
          ? Duration.zero
          : DateTime.now().difference(backgroundedAt);
      if (shouldLockAfterBackground(elapsed: elapsed)) {
        if (mounted) {
          setState(() {
            _unlocked = false;
            _obscured = false;
          });
        }
        _unlock();
      } else {
        if (mounted) setState(() => _obscured = false);
        if (_unlocked) _armIdleTimer();
        else _unlock();
      }
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    AppLockService.instance.enabled.removeListener(_onSettingChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _lockScreen({required bool privacyOnly}) {
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
                Text(
                  privacyOnly ? 'Sleep Tracker приостановлен' : 'Sleep Tracker заблокирован',
                  style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  privacyOnly
                      ? 'Личные данные скрыты до возвращения в приложение.'
                      : 'Подтвердите личность, чтобы открыть дневник сна и личные данные.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.muted, height: 1.45),
                ),
                if (!privacyOnly) ...[
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _authenticating ? null : _unlock,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Разблокировать'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!AppLockService.instance.enabled.value) return widget.child;
    if (_obscured) return _lockScreen(privacyOnly: true);
    if (!_unlocked) return _lockScreen(privacyOnly: false);
    return Listener(
      onPointerDown: _onUserActivity,
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}
