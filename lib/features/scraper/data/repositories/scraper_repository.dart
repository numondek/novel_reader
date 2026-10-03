import '../../../../core/network/dio_client.dart';
import '../../domain/models/extracted_chapter.dart';
import '../../domain/services/novel_site_adapter.dart';
import '../../domain/services/offline_chapter_store.dart';
import '../services/webview_html_fetcher.dart';

class ScraperRepository {
  ScraperRepository({
    required DioClient dioClient,
    required NovelSiteAdapter adapter,
    WebViewHtmlFetcher? webFetcher,
    OfflineChapterStore? offline,
  }) : _dioClient = dioClient,
       _adapter = adapter,
       _webFetcher = webFetcher,
       _offline = offline;

  final DioClient _dioClient;
  final NovelSiteAdapter _adapter;
  final WebViewHtmlFetcher? _webFetcher;
  final OfflineChapterStore? _offline;

  Future<ExtractedChapter> extractChapter(String url) async {
    final uri = Uri.tryParse(url);

    if (uri == null || !uri.hasScheme) {
      throw const PageFetchException('Invalid novel URL.');
    }

    final saved = await _findSaved(url);
    if (saved != null) return saved;

    if (!_adapter.canHandle(uri)) {
      throw const PageFetchException('This novel website is not supported.');
    }

    final html = await _loadHtml(url, uri);

    return _adapter.extract(html: html, url: uri);
  }

  /// A chapter saved by the prefetch feature is served straight from
  /// storage, so it stays readable without a connection; any storage
  /// trouble simply falls through to the network.
  Future<ExtractedChapter?> _findSaved(String url) async {
    final store = _offline;
    if (store == null) return null;

    try {
      return await store.find(url);
    } catch (_) {
      return null;
    }
  }

  Future<String> _loadHtml(String url, Uri uri) async {
    try {
      return await _dioClient.getHtml(
        url,
        headers: _adapter.requestHeaders(uri),
      );
    } on PageFetchException catch (error) {
      final fetcher = _webFetcher;

      if (error.statusCode == 403 && fetcher != null) {
        return fetcher.fetchHtml(url);
      }

      rethrow;
    }
  }
}
