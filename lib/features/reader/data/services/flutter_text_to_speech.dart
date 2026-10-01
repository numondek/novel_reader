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
