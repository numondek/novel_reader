import 'selector_novel_adapter.dart';

class FreeWebNovelAdapter extends SelectorNovelAdapter {
  const FreeWebNovelAdapter();

  @override
  List<String> get hosts => const ['freewebnovel.com'];

  @override
  String get contentSelector => '#article';

  @override
  Map<String, String> requestHeaders(Uri url) => const {
    'Referer': 'https://freewebnovel.com/',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  @override
  String extractTitle(dynamic document) {
    final chapter = document.querySelector('span.chapter')?.text.trim();
    if (chapter != null && chapter.isNotEmpty) {
      return chapter;
    }

    final articleHeading = document.querySelector('#article h4')?.text.trim();
    if (articleHeading != null && articleHeading.isNotEmpty) {
      return articleHeading;
    }

    return super.extractTitle(document);
  }
}
