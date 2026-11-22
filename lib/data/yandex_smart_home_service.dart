import 'dart:convert';

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

  static const _tokenKey = 'yandex_smart_home_access_token';
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.afterFirstUnlockThisDeviceOnly),
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

  Future<String?> readAccessToken() => _storage.read(key: _tokenKey);
  Future<bool> get isConnected async => (await readAccessToken())?.isNotEmpty == true;
  Future<void> disconnect() => _storage.delete(key: _tokenKey);

  Future<Map<String, dynamic>> _get(String path) async {
    final token = await readAccessToken();
    if (token == null || token.isEmpty) {
      throw const YandexSmartHomeException('Сначала подключите аккаунт Яндекса.');
    }
    final response = await _client.get(
      Uri.parse('$_base$path'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 20));
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

  void dispose() => _client.close();
}
