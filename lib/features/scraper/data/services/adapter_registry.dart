import '../../domain/models/extracted_chapter.dart';
import '../../domain/services/novel_site_adapter.dart';

/// Routes requests to the first adapter that handles the URL,
/// falling back to [fallback] for unknown sites.
class AdapterRegistry implements NovelSiteAdapter {
  AdapterRegistry({
    required this.adapters,
    required this.fallback,
  });

  final List<NovelSiteAdapter> adapters;
  final NovelSiteAdapter fallback;

  NovelSiteAdapter resolve(Uri url) {
    for (final adapter in adapters) {
      if (adapter.canHandle(url)) {
        return adapter;
      }
    }
    return fallback;
  }

  @override
  bool canHandle(Uri url) => fallback.canHandle(url);

  @override
  Map<String, String> requestHeaders(Uri url) =>
      resolve(url).requestHeaders(url);

  @override
  Future<ExtractedChapter> extract({
    required String html,
    required Uri url,
  }) {
    return resolve(url).extract(html: html, url: url);
  }
}
