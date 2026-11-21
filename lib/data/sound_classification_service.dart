import 'package:flutter/services.dart';

class SoundClassification {
  const SoundClassification({required this.category, required this.confidence});
  final String category;
  final double confidence;
}

class SoundClassificationService {
  SoundClassificationService._();
  static final instance = SoundClassificationService._();
  static const _channel = MethodChannel('ru.sleeptracker/sound_classifier');

  Future<SoundClassification> classifyFile(String path) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('classifyFile', {'path': path});
      if (result == null) return const SoundClassification(category: 'unknown', confidence: 0);
      final confidence = (result['confidence'] as num?)?.toDouble() ?? 0;
      final category = result['category'] as String? ?? 'unknown';
      if (confidence < 0.55) return const SoundClassification(category: 'unknown', confidence: 0);
      return SoundClassification(category: category, confidence: confidence);
    } on PlatformException {
      return const SoundClassification(category: 'unknown', confidence: 0);
    } on MissingPluginException {
      return const SoundClassification(category: 'unknown', confidence: 0);
    }
  }
}
