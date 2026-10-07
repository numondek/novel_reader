import 'selector_novel_adapter.dart';

class SiteDAdapter extends SelectorNovelAdapter {
  const SiteDAdapter();

  @override
  List<String> get hosts => const [];

  @override
  String get contentSelector => '.chapter-inner';
}
