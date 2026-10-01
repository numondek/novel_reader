abstract interface class TranslationService {
  Future<List<String>> translateParagraphs(
    List<String> paragraphs, {
    required String targetLanguage,
  });
}

class TranslationException implements Exception {
  TranslationException(this.message);

  final String message;

  @override
  String toString() => message;
}
