import 'selector_novel_adapter.dart';

class SiteCAdapter extends SelectorNovelAdapter {
  const SiteCAdapter();

  @override
  List<String> get hosts => const [];

  @override
  String get contentSelector => 'div.reading-content';
}
