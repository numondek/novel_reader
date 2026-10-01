abstract interface class TextToSpeech {
  Future<void> setLanguage(String language);

  Future<void> setSpeechRate(double rate);

  Future<void> speak(String text);

  Future<void> stop();

  void onCompletion(void Function() handler);

  void onCancel(void Function() handler);

  void onError(void Function(dynamic message) handler);
}
