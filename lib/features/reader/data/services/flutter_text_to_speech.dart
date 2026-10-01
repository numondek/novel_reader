import 'package:flutter_tts/flutter_tts.dart';

import '../../domain/services/text_to_speech.dart';

class FlutterTextToSpeech implements TextToSpeech {
  FlutterTextToSpeech() : _tts = FlutterTts();

  final FlutterTts _tts;

  @override
  Future<void> setLanguage(String language) async {
    await _tts.setLanguage(language);
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    await _tts.setSpeechRate(rate);
  }

  @override
  Future<void> setVoice(String name, String locale) async {
    final voice = <String, String>{'name': name};
    if (locale.isNotEmpty) {
      voice['locale'] = locale;
    }

    await _tts.setVoice(voice);
  }

  @override
  Future<List<TtsVoice>> getVoices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) {
        return const [];
      }

      final voices = <TtsVoice>[];

      for (final item in raw) {
        if (item is! Map) continue;

        final name = '${item['name'] ?? ''}';
        final locale = '${item['locale'] ?? ''}';

        if (name.isEmpty) continue;

        voices.add(TtsVoice(name: name, locale: locale));
      }

      return voices;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }

  @override
  void onCompletion(void Function() handler) {
    _tts.setCompletionHandler(handler);
  }

  @override
  void onCancel(void Function() handler) {
    _tts.setCancelHandler(handler);
  }

  @override
  void onError(void Function(dynamic message) handler) {
    _tts.setErrorHandler(handler);
  }
}
