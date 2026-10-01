import '../../../../core/network/dio_client.dart';
import '../../domain/models/extracted_chapter.dart';
import '../../domain/services/novel_site_adapter.dart';
import '../services/webview_html_fetcher.dart';

class ScraperRepository {
  ScraperRepository({
    required DioClient dioClient,
    required NovelSiteAdapter adapter,
    WebViewHtmlFetcher? webFetcher,
  })  : _dioClient = dioClient,
        _adapter = adapter,
        _webFetcher = webFetcher;

  final DioClient _dioClient;
  final NovelSiteAdapter _adapter;
  final WebViewHtmlFetcher? _webFetcher;

  Future<ExtractedChapter> extractChapter(
    String url,
  ) async {
    final uri = Uri.tryParse(url);

    if (uri == null || !uri.hasScheme) {
      throw const PageFetchException('Invalid novel URL.');
    }

    if (!_adapter.canHandle(uri)) {
      throw const PageFetchException(
        'This novel website is not supported.',
      );
    }

    final html = await _loadHtml(url, uri);

    return _adapter.extract(
      html: html,
      url: uri,
    );
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
