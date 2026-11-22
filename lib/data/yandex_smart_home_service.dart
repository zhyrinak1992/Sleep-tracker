import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'sleep_database.dart';

class YandexSmartHomeException implements Exception {
  const YandexSmartHomeException(this.message);
  final String message;
  @override
  String toString() => message;
}

class YandexRoom {
  const YandexRoom({required this.id, required this.name});
  final String id;
  final String name;
}

class YandexSensorDevice {
  const YandexSensorDevice({
    required this.id,
    required this.name,
    required this.roomId,
    required this.roomName,
    required this.online,
    required this.hasTemperature,
    required this.hasHumidity,
  });
  final String id;
  final String name;
  final String? roomId;
  final String? roomName;
  final bool online;
  final bool hasTemperature;
  final bool hasHumidity;
}

class YandexDeviceAuthorization {
  const YandexDeviceAuthorization({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.intervalSeconds,
    required this.expiresInSeconds,
  });
  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final int intervalSeconds;
  final int expiresInSeconds;
}

class YandexHomeSnapshot {
  const YandexHomeSnapshot({required this.rooms, required this.devices});
  final List<YandexRoom> rooms;
  final List<YandexSensorDevice> devices;
}

/// Яндекс Smart Home: только GET-запросы и OAuth scope iot:view.
/// В этом сервисе намеренно отсутствуют методы управления устройствами.
class YandexSmartHomeService {
  YandexSmartHomeService._();
  static final instance = YandexSmartHomeService._();

  static const clientId = 'fb4f08d2d49442589db87e9ee837d670';
  static const _tokenKey = 'yandex_smart_home_access_token';
  static const _refreshTokenKey = 'yandex_smart_home_refresh_token';
  static const _tokenExpiryKey = 'yandex_smart_home_token_expiry';
  static const _deviceIdKey = 'yandex_smart_home_oauth_device_id';
  static const _oauthBase = 'https://oauth.yandex.ru';
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  static const _base = 'https://api.iot.yandex.net/v1.0';
  final http.Client _client = http.Client();

  Future<void> saveAccessToken(String token) async {
    final value = token.trim();
    if (value.isEmpty || value.length > 2048) {
      throw const YandexSmartHomeException('OAuth-токен пустой или имеет недопустимую длину.');
    }
    await _storage.write(key: _tokenKey, value: value);
  }

  Future<String> _oauthDeviceId() async {
    final saved = await _storage.read(key: _deviceIdKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final generated = const Uuid().v4();
    await _storage.write(key: _deviceIdKey, value: generated);
    return generated;
  }

  Future<YandexDeviceAuthorization> requestDeviceAuthorization() async {
    final response = await _client.post(
      Uri.parse('$_oauthBase/device/code'),
      headers: {'Accept': 'application/json'},
      body: {
        'client_id': clientId,
        'device_id': await _oauthDeviceId(),
        'device_name': 'Sleep Tracker (iPhone)',
        'scope': 'iot:view',
      },
    ).timeout(const Duration(seconds: 20));
    final data = _decodeOAuthResponse(response);
    final deviceCode = data['device_code'];
    final userCode = data['user_code'];
    final verificationUrl = data['verification_url'];
    if (deviceCode is! String || userCode is! String || verificationUrl is! String) {
      throw const YandexSmartHomeException('Яндекс не вернул данные для подтверждения доступа.');
    }
    return YandexDeviceAuthorization(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUrl: verificationUrl,
      intervalSeconds: (data['interval'] as num?)?.toInt() ?? 5,
      expiresInSeconds: (data['expires_in'] as num?)?.toInt() ?? 300,
    );
  }

  Map<String, dynamic> _decodeOAuthResponse(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw YandexSmartHomeException('Яндекс OAuth вернул некорректный ответ (HTTP ${response.statusCode}).');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const YandexSmartHomeException('Яндекс OAuth вернул ответ неизвестного формата.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300 || decoded['error'] != null) {
      final error = decoded['error']?.toString();
      final description = decoded['error_description']?.toString();
      throw YandexSmartHomeException(description?.isNotEmpty == true
        ? description!
        : 'Ошибка Яндекс OAuth${error == null ? '' : ': $error'} (HTTP ${response.statusCode}).');
    }
    return decoded;
  }

  Future<void> completeDeviceAuthorization(YandexDeviceAuthorization authorization) async {
    final deadline = DateTime.now().add(Duration(seconds: authorization.expiresInSeconds));
    var interval = authorization.intervalSeconds.clamp(2, 30);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(Duration(seconds: interval));
      if (!DateTime.now().isBefore(deadline)) break;
      final response = await _client.post(
        Uri.parse('$_oauthBase/token'),
        headers: {'Accept': 'application/json'},
        body: {
          'grant_type': 'device_code',
          'code': authorization.deviceCode,
          'client_id': clientId,
          'device_id': await _oauthDeviceId(),
          'device_name': 'Sleep Tracker (iPhone)',
        },
      ).timeout(const Duration(seconds: 20));
      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        throw const YandexSmartHomeException('Не удалось прочитать ответ Яндекс OAuth.');
      }
      if (decoded is! Map<String, dynamic>) {
        throw const YandexSmartHomeException('Яндекс OAuth вернул ответ неизвестного формата.');
      }
      if (response.statusCode >= 200 && response.statusCode < 300 && decoded['access_token'] is String) {
        await _saveOAuthTokens(decoded);
        return;
      }
      final error = decoded['error']?.toString();
      if (error == 'authorization_pending') continue;
      if (error == 'slow_down') {
        interval += 5;
        continue;
      }
      if (error == 'expired_token') {
        throw const YandexSmartHomeException('Время подтверждения истекло. Запустите подключение ещё раз.');
      }
      if (error == 'access_denied') {
        throw const YandexSmartHomeException('Доступ к Яндекс Умному дому не был разрешён.');
      }
      throw YandexSmartHomeException(decoded['error_description']?.toString()
        ?? 'Ошибка получения токена Яндекса${error == null ? '' : ': $error'}.');
    }
    throw const YandexSmartHomeException('Время подтверждения истекло. Запустите подключение ещё раз.');
  }

  Future<void> _saveOAuthTokens(Map<String, dynamic> data) async {
    final access = data['access_token'];
    if (access is! String || access.isEmpty) {
      throw const YandexSmartHomeException('Яндекс не выдал токен доступа.');
    }
    await _storage.write(key: _tokenKey, value: access);
    final refresh = data['refresh_token'];
    if (refresh is String && refresh.isNotEmpty) {
      await _storage.write(key: _refreshTokenKey, value: refresh);
    }
    final expiresIn = (data['expires_in'] as num?)?.toInt();
    if (expiresIn != null && expiresIn > 0) {
      await _storage.write(
        key: _tokenExpiryKey,
        value: DateTime.now().add(Duration(seconds: expiresIn)).toUtc().toIso8601String(),
      );
    }
  }

  Future<bool> _refreshAccessToken() async {
    final refresh = await _storage.read(key: _refreshTokenKey);
    if (refresh == null || refresh.isEmpty) return false;
    final response = await _client.post(
      Uri.parse('$_oauthBase/token'),
      headers: {'Accept': 'application/json'},
      body: {'grant_type': 'refresh_token', 'refresh_token': refresh, 'client_id': clientId},
    ).timeout(const Duration(seconds: 20));
    try {
      final data = _decodeOAuthResponse(response);
      await _saveOAuthTokens(data);
      return true;
    } on YandexSmartHomeException {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _refreshTokenKey);
      await _storage.delete(key: _tokenExpiryKey);
      return false;
    }
  }

  Future<String?> readAccessToken() => _storage.read(key: _tokenKey);
  Future<bool> get isConnected async => (await readAccessToken())?.isNotEmpty == true;
  Future<void> disconnect() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _tokenExpiryKey);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    var token = await readAccessToken();
    if (token == null || token.isEmpty) {
      throw const YandexSmartHomeException('Сначала подключите аккаунт Яндекса.');
    }
    var response = await _client.get(
      Uri.parse('$_base$path'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode == 401 && await _refreshAccessToken()) {
      token = await readAccessToken();
      if (token != null) {
        response = await _client.get(
          Uri.parse('$_base$path'),
          headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 20));
      }
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const YandexSmartHomeException('Яндекс отклонил токен или у него нет разрешения iot:view. Переподключите аккаунт.');
    }
    if (response.statusCode == 429) {
      throw const YandexSmartHomeException('Яндекс временно ограничил частоту запросов. Повторите позже.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw YandexSmartHomeException('Ошибка API Яндекса: HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['status'] == 'error') {
      throw const YandexSmartHomeException('Яндекс вернул некорректный ответ.');
    }
    return decoded;
  }

  Future<YandexHomeSnapshot> fetchHome() async {
    final data = await _get('/user/info');
    final roomNames = <String, String>{};
    final rooms = <YandexRoom>[];
    for (final item in (data['rooms'] as List? ?? const [])) {
      if (item is! Map) continue;
      final id = item['id'];
      final name = item['name'];
      if (id is String && name is String) {
        roomNames[id] = name;
        rooms.add(YandexRoom(id: id, name: name));
        await SleepDatabase.instance.setAppMetadata('yandex_room_name_$id', name);
      }
    }
    final devices = <YandexSensorDevice>[];
    for (final item in (data['devices'] as List? ?? const [])) {
      if (item is! Map) continue;
      final id = item['id'];
      final name = item['name'];
      if (id is! String || name is! String) continue;
      final roomId = item['room'] is String ? item['room'] as String : null;
      final properties = item['properties'] as List? ?? const [];
      var temperature = false;
      var humidity = false;
      for (final property in properties) {
        if (property is! Map || property['retrievable'] != true) continue;
        final parameters = property['parameters'];
        final instance = parameters is Map ? parameters['instance'] : null;
        if (instance == 'temperature') temperature = true;
        if (instance == 'humidity') humidity = true;
      }
      if (temperature || humidity) {
        devices.add(YandexSensorDevice(
          id: id, name: name, roomId: roomId,
          roomName: roomId == null ? null : roomNames[roomId],
          online: item['state'] == 'online',
          hasTemperature: temperature, hasHumidity: humidity,
        ));
      }
    }
    return YandexHomeSnapshot(rooms: rooms, devices: devices);
  }

  /// Получает актуальное состояние одного выбранного датчика и сохраняет только
  /// retrievable temperature/humidity, у которых есть реальный timestamp.
  Future<int> refreshSelectedDevice({
    required String deviceId,
    String? sessionId,
  }) async {
    final data = await _get('/devices/${Uri.encodeComponent(deviceId)}');
    final properties = data['properties'] as List? ?? const [];
    final deviceName = data['name'] as String? ?? deviceId;
    final roomId = data['room'] as String?;
    var roomName = await SleepDatabase.instance.getAppMetadata('yandex_room_name_$roomId');
    var saved = 0;
    for (final property in properties) {
      if (property is! Map || property['retrievable'] != true) continue;
      final parameters = property['parameters'];
      final instance = parameters is Map ? parameters['instance'] : null;
      if (instance != 'temperature' && instance != 'humidity') continue;
      final state = property['state'];
      final rawValue = state is Map ? state['value'] : null;
      final rawUpdated = property['last_updated'];
      if (rawValue is! num || !rawValue.toDouble().isFinite || rawUpdated is! num) continue;
      final measuredAt = DateTime.fromMillisecondsSinceEpoch(
        (rawUpdated * 1000).round(), isUtc: true,
      );
      if (measuredAt.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 2)))) continue;
      final metricType = instance as String;
      final unit = metricType == 'temperature' ? '°C' : '%';
      final stableId = 'yandex_${deviceId}_${metricType}_${rawUpdated.toString()}';
      await SleepDatabase.instance.saveClimateSample(
        id: stableId,
        sessionId: sessionId,
        deviceId: deviceId,
        deviceName: deviceName,
        roomName: roomName,
        metricType: metricType,
        value: rawValue.toDouble(),
        unit: unit,
        source: 'yandex_smart_home',
        measuredAt: measuredAt,
      );
      saved++;
    }
    return saved;
  }


  /// Безопасный фоновый для UI опрос: вызывается только пока приложение активно.
  /// iOS не гарантирует выполнение этого таймера при заблокированном экране.
  Future<int> refreshConfiguredDeviceIfNeeded({
    Duration minimumInterval = const Duration(minutes: 15),
  }) async {
    final deviceId = await SleepDatabase.instance.getAppMetadata('yandex_selected_device_id');
    if (deviceId == null || deviceId.isEmpty || !await isConnected) return 0;
    final latest = await SleepDatabase.instance.getClimateSamples(deviceId: deviceId);
    if (latest.isNotEmpty) {
      final received = DateTime.tryParse(latest.last['received_at'] as String? ?? '');
      if (received != null && DateTime.now().toUtc().difference(received) < minimumInterval) return 0;
    }
    final activeSession = await SleepDatabase.instance.getOpenSession();
    return refreshSelectedDevice(deviceId: deviceId, sessionId: activeSession?.id);
  }

  void dispose() => _client.close();
}
