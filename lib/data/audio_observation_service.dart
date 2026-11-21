import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import 'sleep_database.dart';
import 'notification_service.dart';
import 'sound_classification_service.dart';

/// Event-based microphone monitor. PCM is held in memory only while a sound
/// event is detected; quiet periods are not written to disk. iOS background
/// capture still requires a real-device test and may be interrupted by iOS.
class AudioObservationService {
  AudioObservationService._();
  static final instance = AudioObservationService._();
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  final List<Uint8List> _preRoll = [];
  BytesBuilder? _eventBytes;
  DateTime? _eventStartedAt;
  DateTime? _lastLoudAt;
  bool _observing = false;
  final ValueNotifier<bool> observing = ValueNotifier<bool>(false);
  final ValueNotifier<bool> paused = ValueNotifier<bool>(false);
  bool _paused = false;
  bool get isRecording => _observing;
  int detectedEvents = 0;
  static const int _sampleRate = 16000;
  static const double _rmsThreshold = 0.025;
  static const Duration _silenceToEnd = Duration(milliseconds: 1200);
  static const Duration _maxClip = Duration(seconds: 12);

  Future<void> startObservation() async {
    if (_observing) return;
    if (!await _recorder.hasPermission()) {
      throw StateError('Нет разрешения на использование микрофона.');
    }
    _preRoll.clear();
    _eventBytes = null;
    _eventStartedAt = null;
    _lastLoudAt = null;
    _observing = true;
    _paused = false;
    observing.value = true;
    paused.value = false;
    try {
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits, sampleRate: _sampleRate,
        numChannels: 1, echoCancel: false, noiseSuppress: false,
      ));
      _subscription = stream.listen(_consume, onError: (Object error) {
        _observing = false;
        observing.value = false;
        _paused = false;
        paused.value = false;
      });
    } catch (_) {
      _observing = false;
      observing.value = false;
      _paused = false;
      paused.value = false;
      rethrow;
    }
  }

  void _consume(Uint8List chunk) {
    if (!_observing || _paused || chunk.length < 2) return;
    final now = DateTime.now();
    final samples = chunk.length ~/ 2;
    var sumSquares = 0.0;
    final data = ByteData.sublistView(chunk);
    for (var i = 0; i < samples; i++) {
      final sample = data.getInt16(i * 2, Endian.little) / 32768.0;
      sumSquares += sample * sample;
    }
    final rms = math.sqrt(sumSquares / samples);
    final loud = rms >= _rmsThreshold;

    if (_eventBytes == null && loud) {
      final preRollMicros = _preRoll.fold<int>(0, (total, part) => total + (part.length ~/ 2) * 1000000 ~/ _sampleRate);
      _eventStartedAt = now.subtract(Duration(microseconds: preRollMicros));
      _lastLoudAt = now;
      _eventBytes = BytesBuilder();
      for (final previous in _preRoll) { _eventBytes!.add(previous); }
      _eventBytes!.add(chunk);
      _preRoll.clear();
      return;
    }

    if (_eventBytes == null) {
      _preRoll.add(Uint8List.fromList(chunk));
      while (_preRoll.length > 5) { _preRoll.removeAt(0); }
      return;
    }

    _eventBytes!.add(chunk);
    if (loud) _lastLoudAt = now;
    final eventDuration = now.difference(_eventStartedAt!);
    final silenceDuration = now.difference(_lastLoudAt!);
    if (silenceDuration >= _silenceToEnd || eventDuration >= _maxClip) {
      unawaited(_saveCurrentEvent());
    }
  }

  Future<void> _saveCurrentEvent() async {
    final builder = _eventBytes;
    final started = _eventStartedAt;
    if (builder == null || started == null) return;
    _eventBytes = null;
    _eventStartedAt = null;
    _lastLoudAt = null;
    final pcm = builder.takeBytes();
    if (pcm.length < (_sampleRate * 2)) return; // Ignore clips shorter than 1 second.
    final dir = await getApplicationDocumentsDirectory();
    final audioDir = Directory(p.join(dir.path, 'audio_events'));
    await audioDir.create(recursive: true);
    final eventId = const Uuid().v4();
    final path = p.join(audioDir.path, 'event_$eventId.wav');
    final wav = _wavFile(pcm, _sampleRate, 1, 16);
    await File(path).writeAsBytes(wav, flush: true);
    final session = await SleepDatabase.instance.getOpenSession();
    final capturedAt = started;
    await SleepDatabase.instance.saveAudioEvent(
      id: eventId, sessionId: session?.id, filePath: path,
      category: 'unknown', capturedAt: capturedAt,
      durationMs: (pcm.length / 2 / _sampleRate * 1000).round(),
    );
    final classification = await SoundClassificationService.instance.classifyFile(path);
    if (classification.category != 'unknown') {
      await SleepDatabase.instance.updateAudioClassification(eventId, classification.category, classification.confidence);
    }
    detectedEvents++;
    final allEvents = await SleepDatabase.instance.getAudioEvents();
    await NotificationService.instance.scheduleAudioExpiry(allEvents.map((row) => DateTime.parse(row['expires_at']! as String)));
  }

  Uint8List _wavFile(Uint8List pcm, int sampleRate, int channels, int bitsPerSample) {
    final header = ByteData(44);
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    void textAt(int offset, String value) { for (var i = 0; i < value.length; i++) { header.setUint8(offset + i, value.codeUnitAt(i)); } }
    textAt(0, 'RIFF'); header.setUint32(4, 36 + pcm.length, Endian.little); textAt(8, 'WAVE');
    textAt(12, 'fmt '); header.setUint32(16, 16, Endian.little); header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little); header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little); header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little); textAt(36, 'data'); header.setUint32(40, pcm.length, Endian.little);
    return Uint8List.fromList([...header.buffer.asUint8List(), ...pcm]);
  }

  Future<void> pauseObservation() async {
    if (!_observing || _paused) return;
    _paused = true;
    paused.value = true;
    await _recorder.pause();
    if (_eventBytes != null) await _saveCurrentEvent();
  }

  Future<void> resumeObservation() async {
    if (!_observing || !_paused) return;
    await _recorder.resume();
    _paused = false;
    paused.value = false;
    _preRoll.clear();
  }

  Future<void> stopObservation() async {
    if (!_observing) return;
    _observing = false;
    observing.value = false;
    _paused = false;
    paused.value = false;
    await _subscription?.cancel();
    _subscription = null;
    try { await _recorder.stop(); } catch (_) {}
    if (_eventBytes != null) await _saveCurrentEvent();
    _preRoll.clear();
  }

  Future<void> dispose() async {
    await stopObservation();
    await _recorder.dispose();
  }
}

