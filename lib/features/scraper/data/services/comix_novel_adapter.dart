import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import '../../../../core/network/dio_client.dart';
import '../../domain/services/novel_site_adapter.dart';
import 'api_payload.dart';
import 'generic_novel_adapter.dart';

/// comix.to is a single-page app: neither the chapter text (the
/// page's pictures) nor the chapter list exists in the HTML, both
/// live behind `/api/v1` — and the API only answers requests the
/// site's own JavaScript makes: it signs a token per path and
/// decrypts the answer (see [inPageApiScript]).
///
/// The page carries the ids it needs in `#initial-data`, so the
/// list and the pictures are fetched through the site's own code
/// and written into the markup as ordinary links and images.
class ComixAdapter extends GenericNovelAdapter
    implements ChapterHtmlRefiner, ChapterLister, InPageApiProvider {
  static const _apiTimeoutPages = 60;
  static const _apiPageSize = 100;

  @override
  bool canHandle(Uri url) {
    return url.host.toLowerCase() == 'comix.to';
  }

  @override
  Map<String, String> requestHeaders(Uri url) {
    if (url.path.startsWith('/api/')) {
      return const {
        'Accept': 'application/json, text/plain, */*',
        'X-Requested-With': 'XMLHttpRequest',
      };
    }

    return const {};
  }

  @override
  String inPageApiScript(Uri target) {
    // The site's API client is a module the page already loaded:
    // it signs every request with a path-bound token and unwraps
    // the encrypted answer, so asking through it is the only way
    // to get a plain response.
    return r'''
async (targetUrl) => {
  const target = new URL(targetUrl);
  let moduleUrl = null;

  for (let attempt = 0; attempt < 60 && !moduleUrl; attempt++) {
    const entries = performance.getEntriesByType('resource');
    for (const entry of entries) {
      if (/\/assets\/build\/[^/]+\/dist\/env-[^/]+\.js$/.test(entry.name)) {
        moduleUrl = entry.name;
        break;
      }
    }
    if (!moduleUrl) {
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
  }

  if (!moduleUrl) {
    throw new Error('the site scripts were not ready in time');
  }

  const app = await import(moduleUrl);
  const path = target.pathname.replace(/^\/api\/v1/, '');

  // The token is signed over the path alone, so the query has to
  // travel as parameters, never baked into the URL.
  const params = {};
  target.searchParams.forEach((value, key) => {
    params[key] = value;
  });
  const config = Object.keys(params).length > 0 ? { params } : undefined;

  const data = await app.T.get(path, config);
  return JSON.stringify(data);
}''';
  }

  @override
  Future<String> refine({
    required String html,
    required Uri url,
    required Future<String> Function(Uri url) load,
  }) async {
    final document = parser.parse(html);

    final shell = _initialData(document);
    final read = shell['read'];
    final chapterId = read is Map ? read['chapterId'] : null;

    if (chapterId == null) {
      return html;
    }

    final detailUri = Uri.parse('${url.origin}/api/v1/chapters/$chapterId');
    final detail = _unwrap(decodeJsonPayload(await load(detailUri)));

    final imageUrls = _imageUrlsOf(detail);

    if (imageUrls.isEmpty) {
      throw const PageFetchException(
        'The pictures of this chapter could not be loaded.',
      );
    }

    final body = document.body;
    if (body == null) {
      return html;
    }

    final container = Element.tag('div')
      ..attributes['class'] = 'chapter-content';

    for (final source in imageUrls) {
      container.append(Element.tag('img')..attributes['src'] = source);
    }

    body.nodes.add(container);

    final previous = _navHrefOf(detail['prev']);
    final next = _navHrefOf(detail['next']);

    if (previous != null) {
      body.nodes.add(
        Element.tag('a')
          ..attributes['class'] = 'prev'
          ..attributes['href'] = previous
          ..text = 'Previous chapter',
      );
    }

    if (next != null) {
      body.nodes.add(
        Element.tag('a')
          ..attributes['class'] = 'next'
          ..attributes['href'] = next
          ..text = 'Next chapter',
      );
    }

    return document.outerHtml;
  }

  @override
  Future<String> listingHtml({
    required String html,
    required Uri url,
    required Future<String> Function(Uri url) load,
  }) async {
    final document = parser.parse(html);
    final shell = _initialData(document);

    final read = shell['read'];
    final manga = shell['manga'];

    // The chapters endpoint is addressed by the series handle, not
    // the numeric id — the numeric id is only for the page shell.
    final hid =
        (read is Map ? read['mangaHid'] : null) ??
        (manga is Map ? manga['hid'] : null);

    if (hid is! String || hid.isEmpty) {
      throw const PageFetchException('Could not find this series on comix.to.');
    }

    final anchors = <String>[];
    var page = 1;
    var lastPage = 1;

    do {
      final listUri = Uri.parse(
        '${url.origin}/api/v1/manga/$hid/chapters'
        '?page=$page&limit=$_apiPageSize',
      );

      final data = _unwrap(decodeJsonPayload(await load(listUri)));
      final items = data['items'];

      if (items is List) {
        for (var index = 0; index < items.length; index++) {
          final item = items[index];
          if (item is! Map) {
            continue;
          }

          final href = _chapterHref(item, url);
          if (href == null) {
            continue;
          }

          anchors.add('<a href="$href">${_chapterLabel(item, index)}</a>');
        }
      }

      lastPage = _lastPageOf(data);
      page++;
    } while (page <= lastPage && page <= _apiTimeoutPages);

    if (anchors.isEmpty) {
      throw const PageFetchException('This series has no chapters yet.');
    }

    return '<div class="chapter-list">${anchors.join()}</div>';
  }

  /// The SPA's hydration payload: ids and routes the page bootstraps
  /// from, sitting in a JSON script tag.
  Map<String, dynamic> _initialData(Document document) {
    final script = document.querySelector('#initial-data');

    if (script == null) {
      return const {};
    }

    return decodeJsonPayload(script.text);
  }

  Map<String, dynamic> _unwrap(Map<String, dynamic> payload) {
    final result = payload['result'];

    if (result is Map<String, dynamic>) {
      return result;
    }

    return payload;
  }

  List<String> _imageUrlsOf(Map<String, dynamic> detail) {
    final pages = detail['pages'];
    if (pages is! Map) {
      return const [];
    }

    final base = pages['baseUrl'];
    final baseUrl = base is String ? base : '';

    final items = pages['items'];
    if (items is! List) {
      return const [];
    }

    final urls = <String>[];

    for (final item in items) {
      if (item is Map && item['url'] is String) {
        urls.add('$baseUrl${item['url']}');
      }
    }

    return urls;
  }

  /// A neighbouring chapter's address, when the API names one.
  String? _navHrefOf(Object? nav) {
    if (nav is Map) {
      final href = nav['url'];

      if (href is String && href.isNotEmpty) {
        return href;
      }

      return null;
    }

    if (nav is String && nav.isNotEmpty) {
      return nav;
    }

    return null;
  }

  String? _chapterHref(Map item, Uri pageUrl) {
    final href = item['url'];

    if (href is String && href.isNotEmpty) {
      return href;
    }

    // Without a server-provided address the chapter is still
    // reachable: the reader builds the same shape of URL.
    final chapterId = item['id'];
    final number = item['number'];

    if (chapterId == null || number == null) {
      return null;
    }

    final segments = pageUrl.pathSegments;
    final titleIndex = segments.indexOf('title');
    if (titleIndex < 0 || titleIndex + 1 >= segments.length) {
      return null;
    }

    return '/title/${segments[titleIndex + 1]}/$chapterId-chapter-$number';
  }

  String _chapterLabel(Map item, int index) {
    final number = item['number'];
    final name = item['name'];

    final label =
        'Chapter ${number ?? index + 1}'
        '${name is String && name.trim().isNotEmpty ? ' - ${name.trim()}' : ''}';

    return label;
  }

  int _lastPageOf(Map<String, dynamic> data) {
    final meta = data['meta'];
    final source = meta is Map ? meta : data;

    final lastPage = source['lastPage'] ?? source['last_page'];

    return lastPage is int && lastPage > 0 ? lastPage : 1;
  }
}
