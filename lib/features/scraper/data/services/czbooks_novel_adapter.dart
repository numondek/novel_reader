import 'selector_novel_adapter.dart';

class CzbooksAdapter extends SelectorNovelAdapter {
  const CzbooksAdapter();

  @override
  List<String> get hosts => const ['czbooks.net'];

  @override
  String get contentSelector => 'div.content';

  @override
  String extractTitle(dynamic document) {
    final title = super.extractTitle(document);

    final suffixIndex = title.lastIndexOf(' | ');
    if (suffixIndex > 0) {
      return title.substring(0, suffixIndex).trim();
    }

    return title;
  }
}
