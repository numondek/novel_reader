abstract interface class TextToSpeech {
  Future<void> setLanguage(String language);

  Future<void> setSpeechRate(double rate);

  Future<void> setVoice(String name, String locale);

  Future<List<TtsVoice>> getVoices();

  Future<void> speak(String text);

  Future<void> stop();

  void onCompletion(void Function() handler);

  void onCancel(void Function() handler);

  void onError(void Function(dynamic message) handler);
}

/// A voice offered by the device's speech engine.
class TtsVoice {
  const TtsVoice({required this.name, required this.locale});

  final String name;
  final String locale;

  String get label =>
      locale.isEmpty ? name : '$name ($locale)';
}
