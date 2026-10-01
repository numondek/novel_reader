import 'selector_novel_adapter.dart';

class SiteAAdapter extends SelectorNovelAdapter {
  const SiteAAdapter();

  @override
  List<String> get hosts => const [];

  @override
  String get contentSelector => 'div.chapter-content';
}