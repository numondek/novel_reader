import '../../../../core/network/dio_client.dart';
import '../../domain/models/extracted_chapter.dart';
import '../../domain/services/novel_site_adapter.dart';
import '../../domain/services/offline_chapter_store.dart';
import '../services/adapter_registry.dart';
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

    var html = await _loadHtml(url, uri);

    final impl = _resolveAdapter(uri);

    if (impl is ChapterHtmlRefiner) {
      html = await impl.refine(html: html, url: uri, load: _loaderFor(impl));
    }

    return _adapter.extract(html: html, url: uri);
  }

  /// Fetches the raw HTML of [url], used to list the chapters of a
  /// series or contents page.
  Future<String> loadHtml(String url) async {
    final uri = Uri.tryParse(url);

    if (uri == null || !uri.hasScheme) {
      throw const PageFetchException('Invalid URL.');
    }

    if (!_adapter.canHandle(uri)) {
      throw const PageFetchException('This website is not supported.');
    }

    final html = await _loadHtml(url, uri);

    final impl = _resolveAdapter(uri);

    if (impl is ChapterLister) {
      return impl.listingHtml(html: html, url: uri, load: _loaderFor(impl));
    }

    return html;
  }

  /// The adapter behind [uri] — the registry routes per host, and
  /// its capabilities (refining, listing) must match the URL too.
  NovelSiteAdapter _resolveAdapter(Uri uri) {
    final adapter = _adapter;

    if (adapter is AdapterRegistry) {
      return adapter.resolve(uri);
    }

    return adapter;
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

  Future<String> _load(Uri uri) => _loadHtml(uri.toString(), uri);

  /// The fetch for [impl]'s follow-up requests: through the site's
  /// own scripts when the adapter provides them, plain HTTP
  /// otherwise.
  Future<String> Function(Uri uri) _loaderFor(NovelSiteAdapter impl) =>
      impl is InPageApiProvider ? _api : _load;

  /// An API URL only the site's own code can ask — the request runs
  /// inside a page on the site's origin, signed by the scripts that
  /// live there; without a session to run it in, it falls back to
  /// plain HTTP.
  Future<String> _api(Uri uri) {
    final fetcher = _webFetcher;
    final impl = _resolveAdapter(uri);

    if (impl is InPageApiProvider && fetcher is PageSessionFetcher) {
      return fetcher.fetchViaPage(
        uri.toString(),
        script: impl.inPageApiScript(uri),
      );
    }

    return _load(uri);
  }

  Future<String> _loadHtml(String url, Uri uri) async {
    try {
      return await _dioClient.getHtml(
        url,
        headers: _adapter.requestHeaders(uri),
      );
    } on PageFetchException catch (error) {
      final fetcher = _webFetcher;

      if (error.statusCode != 403 || fetcher == null) {
        rethrow;
      }

      try {
        return await fetcher.fetchHtml(url);
      } on PageFetchException catch (directError) {
        // The built-in browser was refused too. Running the
        // request from inside a page on the same origin still
        // carries the cookies and fingerprint the site expects.
        if (directError.statusCode == 403 && fetcher is PageSessionFetcher) {
          return fetcher.fetchViaPage(url);
        }

        rethrow;
      }
    }
  }
}
