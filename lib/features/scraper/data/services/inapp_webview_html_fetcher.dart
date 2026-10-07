import 'dart:async';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../core/network/dio_client.dart';
import 'webview_html_fetcher.dart';

/// Fetches page HTML through the platform WebView (Chrome / WKWebView),
/// which carries a real browser network fingerprint. Used as a fallback
/// when the plain HTTP client is blocked with HTTP 403.
class InAppWebViewHtmlFetcher
    implements WebViewHtmlFetcher, PageSessionFetcher {
  static const Duration timeout = Duration(seconds: 30);

  @override
  Future<String> fetchHtml(String url) async {
    final completer = Completer<String>();

    void fail(Object error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }

    final headless = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        useShouldOverrideUrlLoading: false,
        supportZoom: false,
      ),
      onLoadStop: (controller, _) async {
        try {
          final result = await controller.evaluateJavascript(
            source: 'document.documentElement.outerHTML',
          );

          if (result is String && result.isNotEmpty) {
            if (!completer.isCompleted) {
              completer.complete(result);
            }
          } else {
            fail(
              const PageFetchException(
                'The page had no content in the built-in browser.',
              ),
            );
          }
        } catch (error) {
          fail(error);
        }
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame != false) {
          fail(
            PageFetchException(
              'Could not load the page in the built-in browser: '
              '${error.description}',
            ),
          );
        }
      },
      onReceivedHttpError: (controller, request, response) {
        final status = response.statusCode ?? 0;

        if (request.isForMainFrame != false && status >= 400) {
          fail(
            PageFetchException(
              'The site refused the built-in browser too (HTTP $status).',
              statusCode: status,
            ),
          );
        }
      },
    );

    try {
      await headless.run();

      final controller = headless.webViewController;
      if (controller == null) {
        throw const PageFetchException('Could not start the built-in browser.');
      }

      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));

      return await completer.future.timeout(timeout);
    } on TimeoutException {
      throw const PageFetchException(
        'The built-in browser timed out while loading the page. '
        'Try again.',
      );
    } finally {
      try {
        await headless.dispose();
      } catch (_) {}
    }
  }

  /// Runs [url] as a `fetch()` from a page on the same origin, so
  /// the request leaves with that session's cookies, headers and
  /// fingerprint — what a site behind a bot check expects from its
  /// own scripts. With [script] (a JavaScript function expression
  /// `async (targetUrl) => String`) that function runs instead, for
  /// sites where only the site's own code can make the request — a
  /// token it signs, a payload it decrypts.
  ///
  /// The text travels back through a JavaScript handler rather than
  /// the evaluation result, so it arrives whether or not the
  /// platform WebView awaits the Promise.
  @override
  Future<String> fetchViaPage(String url, {String? script}) async {
    final target = Uri.tryParse(url);

    if (target == null || !target.hasScheme || target.host.isEmpty) {
      throw const PageFetchException('Invalid URL.');
    }

    final handlerName = 'pageFetch_${DateTime.now().microsecondsSinceEpoch}';

    final completer = Completer<String>();

    void fail(Object error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }

    final headless = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        useShouldOverrideUrlLoading: false,
        supportZoom: false,
      ),
      onLoadStop: (controller, _) async {
        try {
          final path =
              '${target.path}${target.hasQuery ? '?${target.query}' : ''}';

          final expression =
              script != null
                  ? '($script)(${jsonEncode(url)})'
                  : 'fetch(${jsonEncode(path)}, {'
                      'credentials: "include", '
                      'headers: {'
                      '"X-Requested-With": "XMLHttpRequest", '
                      '"Accept": "application/json, text/plain, */*"'
                      '}'
                      '}).then((response) => response.text())';

          final name = jsonEncode(handlerName);
          final source =
              'Promise.resolve()\n'
              '.then(() => ($expression))\n'
              '.then((value) => window.flutter_inappwebview'
              '.callHandler($name, typeof value === "string" ? value :'
              ' JSON.stringify(value)))\n'
              '.catch((error) => window.flutter_inappwebview'
              '.callHandler($name, "ERROR: " +'
              ' (error && error.message ? error.message : error)));';

          final result = await controller.evaluateJavascript(source: source);

          // Platforms that await the Promise hand the text straight
          // back; the handler path fills in for the rest.
          if (result is String &&
              result.isNotEmpty &&
              result != 'null' &&
              !result.startsWith('ERROR: ') &&
              !completer.isCompleted) {
            completer.complete(result);
          }
        } catch (error) {
          fail(error);
        }
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame != false) {
          fail(
            PageFetchException(
              'Could not start the built-in browser: ${error.description}',
            ),
          );
        }
      },
      onReceivedHttpError: (controller, request, response) {
        final status = response.statusCode ?? 0;

        if (request.isForMainFrame != false && status >= 400) {
          fail(
            PageFetchException(
              'The site refused the built-in browser too (HTTP $status).',
              statusCode: status,
            ),
          );
        }
      },
    );

    try {
      await headless.run();

      final controller = headless.webViewController;
      if (controller == null) {
        throw const PageFetchException('Could not start the built-in browser.');
      }

      controller.addJavaScriptHandler(
        handlerName: handlerName,
        callback: (arguments) {
          final value = arguments.isNotEmpty ? arguments.first : null;

          if (value is! String || value.isEmpty || value == 'null') {
            fail(
              const PageFetchException(
                'The site sent no data from its own browser session.',
              ),
            );
          } else if (value.startsWith('ERROR: ')) {
            fail(
              PageFetchException(
                'The page session could not run the request: '
                '${value.substring('ERROR: '.length)}',
              ),
            );
          } else if (!completer.isCompleted) {
            completer.complete(value);
          }

          return null;
        },
      );

      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri('${target.origin}/')),
      );

      return await completer.future.timeout(timeout);
    } on TimeoutException {
      throw const PageFetchException(
        'The built-in browser timed out while loading the page. '
        'Try again.',
      );
    } finally {
      try {
        await headless.dispose();
      } catch (_) {}
    }
  }
}
