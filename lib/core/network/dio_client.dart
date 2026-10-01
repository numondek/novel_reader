import 'package:dio/dio.dart';

/// Fetch failure with a user-friendly [message] and the HTTP
/// [statusCode] (if any), so callers can decide on fallbacks.
class PageFetchException implements Exception {
  const PageFetchException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class DioClient {
  DioClient()
      : dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 15),
            headers: {
              'User-Agent': desktopUserAgent,
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'en-US,en;q=0.9',
            },
          ),
        );

  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 '
      '(KHTML, like Gecko) '
      'Chrome/120.0 Safari/537.36';

  static const String mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 10) '
      'AppleWebKit/537.36 '
      '(KHTML, like Gecko) '
      'Chrome/120.0 Mobile Safari/537.36';

  final Dio dio;

  Future<String> getHtml(
    String url, {
    Map<String, String>? headers,
  }) async {
    final uri = Uri.tryParse(url);

    try {
      return await _fetch(url, headers);
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      final isRetryable =
          status == 403 || status == 429 || status == 408;

      if (!isRetryable) {
        throw _pageError(error);
      }

      try {
        return await _fetch(url, {
          ...?headers,
          'User-Agent': mobileUserAgent,
          if (uri != null && uri.hasAuthority)
            'Referer': '${uri.origin}/',
        });
      } on DioException catch (retryError) {
        throw _pageError(retryError);
      }
    }
  }

  PageFetchException _pageError(DioException error) {
    return PageFetchException(
      friendlyMessage(error),
      statusCode: error.response?.statusCode,
    );
  }

  Future<String> _fetch(
    String url,
    Map<String, String>? headers,
  ) async {
    final response = await dio.get<String>(
      url,
      options: Options(
        headers: headers,
        responseType: ResponseType.plain,
      ),
    );

    final status = response.statusCode;

    if (status != null && status != 200) {
      throw PageFetchException(
        'Failed to load webpage. Status code: $status',
        statusCode: status,
      );
    }

    final data = response.data;

    if (data == null || data.isEmpty) {
      throw const PageFetchException(
        'The webpage returned empty content.',
      );
    }

    return data;
  }

  static String friendlyMessage(DioException error) {
    final status = error.response?.statusCode;

    if (status == 403) {
      return '403 - the site refused the request. '
          'It may be blocking automated access.';
    }

    if (status == 429) {
      return '429 - too many requests. '
          'Please wait a moment and try again.';
    }

    if (status == 408 ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'The request timed out. '
          'Check your connection and try again.';
    }

    if (error.type == DioExceptionType.connectionError) {
      return 'No internet connection.';
    }

    if (status != null) {
      return 'Failed to load the page (HTTP $status).';
    }

    return 'Could not reach the website. '
        'Check your connection and try again.';
  }
}
