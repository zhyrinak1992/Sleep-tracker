import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-native biometric gate. Only the enabled flag is stored by the app;
/// biometric templates and secrets remain managed by iOS.
class AppLockService {
  AppLockService._();
  static final AppLockService instance = AppLockService._();

  static const _enabledKey = 'app_lock_enabled';
  final LocalAuthentication _auth = LocalAuthentication();
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    enabled.value = preferences.getBool(_enabledKey) ?? false;
  }

  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate({String reason = 'Разблокируйте доступ к Sleep Tracker'}) async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          sensitiveTransaction: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, value);
    enabled.value = value;
  }
}
