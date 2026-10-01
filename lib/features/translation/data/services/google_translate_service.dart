import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import '../../domain/services/translation_service.dart';

/// Google Translate via the free `translate.googleapis.com` (gtx)
/// endpoint — no API key required.
///
/// Requests are sent as POST form data: long Chinese batches exceed
/// the ~16KB GET URL limit and get rejected with HTTP 400.
class GoogleTranslateService implements TranslationService {
  GoogleTranslateService({
    Dio? dio,
    int maxAttempts = 3,
    Duration retryBaseDelay = const Duration(milliseconds: 400),
  })  : _dio = dio ?? _createDio(),
        _maxAttempts = maxAttempts < 1 ? 1 : maxAttempts,
        _retryBaseDelay = retryBaseDelay;

  final Dio _dio;
  final int _maxAttempts;
  final Duration _retryBaseDelay;

  static const String endpoint =
      'https://translate.googleapis.com/translate_a/single';

  /// Max characters sent per request; paragraphs are batched with
  /// newline separators up to this size.
  static const int maxBatchChars = 4000;

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 '
              '(KHTML, like Gecko) '
              'Chrome/120.0 Safari/537.36',
        },
      ),
    );
  }

  @override
  Future<List<String>> translateParagraphs(
    List<String> paragraphs, {
    required String targetLanguage,
  }) async {
    if (paragraphs.isEmpty) {
      return const [];
    }

    final results = <String>[];

    for (final batch in _batches(paragraphs)) {
      results.addAll(
        await _translateBatch(batch, targetLanguage),
      );
    }

    return results;
  }

  List<List<String>> _batches(List<String> paragraphs) {
    final batches = <List<String>>[];
    var batch = <String>[];
    var length = 0;

    for (final paragraph in paragraphs) {
      final flat = paragraph.replaceAll('\n', ' ');
      final added = flat.length + 1;

      if (batch.isNotEmpty && length + added > maxBatchChars) {
        batches.add(batch);
        batch = <String>[];
        length = 0;
      }

      batch.add(flat);
      length += added;
    }

    if (batch.isNotEmpty) {
      batches.add(batch);
    }

    return batches;
  }

  Future<List<String>> _translateBatch(
    List<String> paragraphs,
    String targetLanguage,
  ) async {
    final joined = paragraphs.join('\n');
    final translated = await _request(joined, targetLanguage);
    final lines = translated.split('\n');

    if (lines.length == paragraphs.length) {
      return lines.map((line) => line.trim()).toList();
    }

    // Google altered the line count — translate one by one.
    final fallback = <String>[];

    for (final paragraph in paragraphs) {
      fallback.add(
        (await _request(paragraph, targetLanguage)).trim(),
      );
    }

    return fallback;
  }

  Future<String> _request(
    String text,
    String targetLanguage,
  ) async {
    DioException? lastError;

    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      if (attempt > 1) {
        await Future<void>.delayed(_retryDelay(lastError!, attempt));
      }

      try {
        final response = await _dio.post<List<dynamic>>(
          endpoint,
          queryParameters: {
            'client': 'gtx',
            'sl': 'auto',
            'tl': targetLanguage,
            'dt': 't',
          },
          data: 'q=${Uri.encodeComponent(text)}',
          options: Options(
            contentType: 'application/x-www-form-urlencoded',
          ),
        );

        return _parse(response.data);
      } on DioException catch (e) {
        lastError = e;

        developer.log(
          'translate attempt $attempt/$_maxAttempts failed: '
          '${e.type} status=${e.response?.statusCode} ${e.message}',
          name: 'translate',
        );

        if (!_isRetryable(e)) {
          throw TranslationException(_describe(e));
        }

        if (attempt >= _maxAttemptsFor(e)) {
          throw TranslationException(_describe(e));
        }
      }
    }

    throw TranslationException(_describe(lastError!));
  }

  bool _isRetryable(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return true;
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        return status == 408 ||
            status == 429 ||
            (status != null && status >= 500);
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
        return false;
    }
  }

  int _maxAttemptsFor(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        // Connection problems: only one retry — a blocked or offline
        // network will not heal within a reading session.
        return 2;
      default:
        return _maxAttempts;
    }
  }

  Duration _retryDelay(DioException e, int attempt) {
    var factor = 1;
    if (e.response?.statusCode == 429) {
      factor = 3;
    }

    return Duration(
      milliseconds:
          _retryBaseDelay.inMilliseconds * attempt * factor,
    );
  }

  String _describe(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return 'Translation failed: timed out. '
            'Check your connection and try again.';
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return 'Translation failed: could not reach Google Translate. '
            'If Google is blocked on your network, connect to a VPN '
            'and try again.';
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        if (status == 429) {
          return 'Translation failed: rate limited by Google. '
              'Wait a minute and try again.';
        }
        return 'Translation failed (HTTP ${status ?? 'error'}). '
            'Try again later.';
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
        return 'Translation failed. Check your connection and try again.';
    }
  }

  static String _parse(List<dynamic>? data) {
    if (data == null || data.isEmpty || data.first is! List) {
      throw TranslationException(
        'Translation failed. Unexpected response.',
      );
    }

    final segments = data.first as List;
    final buffer = StringBuffer();

    for (final segment in segments) {
      if (segment is List &&
          segment.isNotEmpty &&
          segment.first is String) {
        buffer.write(segment.first);
      }
    }

    final text = buffer.toString();

    if (text.isEmpty) {
      throw TranslationException('Translation failed. Empty translation.');
    }

    return text;
  }
}
