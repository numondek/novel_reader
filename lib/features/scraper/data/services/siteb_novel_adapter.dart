import 'selector_novel_adapter.dart';

class SiteBAdapter extends SelectorNovelAdapter {
  const SiteBAdapter();

  @override
  List<String> get hosts => const [];

  @override
  String get contentSelector => 'article.chapter-content';
}