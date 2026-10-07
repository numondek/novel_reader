import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/network/dio_client.dart';
import 'package:novel_reader/features/scraper/data/repositories/scraper_repository.dart';
import 'package:novel_reader/features/scraper/data/services/adapter_registry.dart';
import 'package:novel_reader/features/scraper/data/services/generic_novel_adapter.dart';
import 'package:novel_reader/features/scraper/data/services/webview_html_fetcher.dart';
import 'package:novel_reader/features/scraper/domain/models/extracted_chapter.dart';
import 'package:novel_reader/features/scraper/domain/services/novel_site_adapter.dart';

class _Dio extends DioClient {
  _Dio(this.responses);

  final Map<String, String> responses;

  @override
  Future<String> getHtml(String url, {Map<String, String>? headers}) async {
    final body = responses[url];

    if (body == null) {
      throw StateError('no response for $url');
    }

    return body;
  }
}

class _Dio403 extends DioClient {
  @override
  Future<String> getHtml(String url, {Map<String, String>? headers}) {
    throw const PageFetchException('refused', statusCode: 403);
  }
}

class _RefinerAdapter implements ChapterHtmlRefiner {
  String? extractedHtml;
  final loaded = <String>[];

  @override
  bool canHandle(Uri url) => url.host == 'x.com';

  @override
  Map<String, String> requestHeaders(Uri url) => const {};

  @override
  Future<String> refine({
    required String html,
    required Uri url,
    required Future<String> Function(Uri url) load,
  }) async {
    final second = await load(Uri.parse('https://x.com/content'));
    loaded.add(second);

    return '<div>$html|$second</div>';
  }

  @override
  Future<ExtractedChapter> extract({
    required String html,
    required Uri url,
  }) async {
    extractedHtml = html;

    return ExtractedChapter(title: 't', paragraphs: const [], url: '$url');
  }
}

class _ListerAdapter implements ChapterLister {
  @override
  bool canHandle(Uri url) => url.host == 'y.com';

  @override
  Map<String, String> requestHeaders(Uri url) => const {};

  @override
  Future<String> listingHtml({
    required String html,
    required Uri url,
    required Future<String> Function(Uri url) load,
  }) async {
    return 'LIST:$html';
  }

  @override
  Future<ExtractedChapter> extract({
    required String html,
    required Uri url,
  }) async {
    return ExtractedChapter(title: 't', paragraphs: const [], url: '$url');
  }
}

class _ApiAdapter implements ChapterHtmlRefiner, InPageApiProvider {
  String? extractedHtml;

  @override
  bool canHandle(Uri url) => url.host == 'x.com';

  @override
  Map<String, String> requestHeaders(Uri url) => const {};

  @override
  String inPageApiScript(Uri target) => 'SCRIPT:${target.path}';

  @override
  Future<String> refine({
    required String html,
    required Uri url,
    required Future<String> Function(Uri url) load,
  }) async {
    final data = await load(Uri.parse('${url.origin}/api/data'));

    return '<div>$html|$data</div>';
  }

  @override
  Future<ExtractedChapter> extract({
    required String html,
    required Uri url,
  }) async {
    extractedHtml = html;

    return ExtractedChapter(title: 't', paragraphs: const [], url: '$url');
  }
}

class _DirectFetcher implements WebViewHtmlFetcher {
  int calls = 0;

  @override
  Future<String> fetchHtml(String url) async {
    calls += 1;

    throw const PageFetchException('refused', statusCode: 403);
  }
}

class _SessionFetcher implements PageSessionFetcher {
  int directCalls = 0;
  int sessionCalls = 0;
  final apiCalls = <(String, String?)>[];

  @override
  Future<String> fetchHtml(String url) async {
    directCalls += 1;

    throw const PageFetchException('refused', statusCode: 403);
  }

  @override
  Future<String> fetchViaPage(String url, {String? script}) async {
    if (script != null) {
      apiCalls.add((url, script));
      return 'API_JSON';
    }

    sessionCalls += 1;

    return 'FROM_PAGE';
  }
}

void main() {
  test('a refiner sees the page and rewrites it before extraction', () async {
    final adapter = _RefinerAdapter();

    final repository = ScraperRepository(
      dioClient: _Dio({
        'https://x.com/a': 'PAGE',
        'https://x.com/content': 'CONTENT',
      }),
      adapter: adapter,
    );

    await repository.extractChapter('https://x.com/a');

    expect(adapter.loaded, ['CONTENT']);
    expect(adapter.extractedHtml, '<div>PAGE|CONTENT</div>');
  });

  test('the registry resolves the refiner behind the URL', () async {
    final adapter = _RefinerAdapter();

    final repository = ScraperRepository(
      dioClient: _Dio({
        'https://x.com/a': 'PAGE',
        'https://x.com/content': 'CONTENT',
      }),
      adapter: AdapterRegistry(
        adapters: [adapter],
        fallback: GenericNovelAdapter(),
      ),
    );

    await repository.extractChapter('https://x.com/a');

    expect(adapter.extractedHtml, '<div>PAGE|CONTENT</div>');
  });

  test('a lister turns the loaded page into the chapter list', () async {
    final repository = ScraperRepository(
      dioClient: _Dio({'https://y.com/series': 'SHELL'}),
      adapter: _ListerAdapter(),
    );

    final listing = await repository.loadHtml('https://y.com/series');

    expect(listing, 'LIST:SHELL');
  });

  test('a refused request falls back to the browser session', () async {
    final fetcher = _SessionFetcher();

    final repository = ScraperRepository(
      dioClient: _Dio403(),
      adapter: GenericNovelAdapter(),
      webFetcher: fetcher,
    );

    final html = await repository.loadHtml('https://blocked.com/page');

    expect(html, 'FROM_PAGE');
    expect(fetcher.directCalls, 1);
    expect(fetcher.sessionCalls, 1);
  });

  test('without the session capability the refusal stands', () async {
    final fetcher = _DirectFetcher();

    final repository = ScraperRepository(
      dioClient: _Dio403(),
      adapter: GenericNovelAdapter(),
      webFetcher: fetcher,
    );

    await expectLater(
      repository.loadHtml('https://blocked.com/page'),
      throwsA(
        isA<PageFetchException>().having(
          (error) => error.statusCode,
          'statusCode',
          403,
        ),
      ),
    );
    expect(fetcher.calls, 1);
  });

  test('an api-backed refiner asks through the page session', () async {
    final adapter = _ApiAdapter();
    final fetcher = _SessionFetcher();

    final repository = ScraperRepository(
      dioClient: _Dio403(),
      adapter: AdapterRegistry(
        adapters: [adapter],
        fallback: GenericNovelAdapter(),
      ),
      webFetcher: fetcher,
    );

    await repository.extractChapter('https://x.com/chapter');

    expect(adapter.extractedHtml, '<div>FROM_PAGE|API_JSON</div>');
    expect(fetcher.apiCalls, [('https://x.com/api/data', 'SCRIPT:/api/data')]);
    expect(fetcher.sessionCalls, 1);
  });
}
