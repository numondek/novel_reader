import '../models/extracted_chapter.dart';

abstract interface class NovelSiteAdapter {
  bool canHandle(Uri url);

  Map<String, String> requestHeaders(Uri url) => const {};

  Future<ExtractedChapter> extract({required String html, required Uri url});
}

/// A site whose chapter text only arrives with a second request —
/// a token-gated endpoint behind the page, an API behind the SPA.
///
/// [refine] turns the loaded page into markup the regular
/// extraction understands, using [load] for any further fetches.
abstract interface class ChapterHtmlRefiner implements NovelSiteAdapter {
  Future<String> refine({
    required String html,
    required Uri url,
    required Future<String> Function(Uri url) load,
  });
}

/// A site whose chapter list lives behind an API instead of the
/// page markup: turns the loaded page into link-shaped HTML so the
/// usual contents-page pass can read it.
abstract interface class ChapterLister implements NovelSiteAdapter {
  Future<String> listingHtml({
    required String html,
    required Uri url,
    required Future<String> Function(Uri url) load,
  });
}

/// A site whose API only answers its own JavaScript — a token the
/// page's scripts sign, a payload they decrypt.
///
/// The repository then hands such an adapter a [load] that runs
/// [inPageApiScript] inside a page on the site's origin instead of
/// a plain HTTP request.
abstract interface class InPageApiProvider implements NovelSiteAdapter {
  /// A JavaScript function expression `async (targetUrl) => String`,
  /// evaluated in a same-origin page, resolving to the JSON text of
  /// the API response for [target].
  String inPageApiScript(Uri target);
}
