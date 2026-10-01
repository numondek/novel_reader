import '../models/extracted_chapter.dart';

abstract interface class NovelSiteAdapter {
  bool canHandle(Uri url);

  Map<String, String> requestHeaders(Uri url) => const {};

  Future<ExtractedChapter> extract({
    required String html,
    required Uri url,
  });
}
