import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../core/network/dio_client.dart';
import 'webview_html_fetcher.dart';

/// Fetches page HTML through the platform WebView (Chrome / WKWebView),
/// which carries a real browser network fingerprint. Used as a fallback
/// when the plain HTTP client is blocked with HTTP 403.
class InAppWebViewHtmlFetcher implements WebViewHtmlFetcher {
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
            fail(const PageFetchException(
              'The page had no content in the built-in browser.',
            ));
          }
        } catch (error) {
          fail(error);
        }
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame != false) {
          fail(PageFetchException(
            'Could not load the page in the built-in browser: '
            '${error.description}',
          ));
        }
      },
      onReceivedHttpError: (controller, request, response) {
        final status = response.statusCode ?? 0;

        if (request.isForMainFrame != false && status >= 400) {
          fail(PageFetchException(
            'The site refused the built-in browser too (HTTP $status).',
            statusCode: status,
          ));
        }
      },
    );

    try {
      await headless.run();

      final controller = headless.webViewController;
      if (controller == null) {
        throw const PageFetchException(
          'Could not start the built-in browser.',
        );
      }

      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
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
