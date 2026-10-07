abstract interface class WebViewHtmlFetcher {
  Future<String> fetchHtml(String url);
}

/// A fetcher that can run a request from inside a page session.
///
/// The page's own origin, cookies and fingerprint go with the
/// request, so sites that refuse a plain HTTP client (a bot check,
/// a token the browser carries) answer this the same way they
/// answer their own scripts.
abstract interface class PageSessionFetcher implements WebViewHtmlFetcher {
  /// Runs [url] from inside a page on its origin — by default as a
  /// plain `fetch()`. With [script] (a JavaScript function
  /// expression `async (targetUrl) => String`) that function runs
  /// instead, for sites whose own code has to make the request.
  Future<String> fetchViaPage(String url, {String? script});
}
