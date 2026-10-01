import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/translation/data/services/google_translate_service.dart';

class FakeResponse {
  const FakeResponse(this.body, {this.status = 200});

  final String body;
  final int status;
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final FakeResponse Function(String q) handler;
  final List<String> queries = <String>[];
  final List<String> methods = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    methods.add(options.method);

    final q = await _extractQ(options, requestStream);
    queries.add(q);

    final response = handler(q);

    return ResponseBody.fromString(
      response.body,
      response.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  Future<String> _extractQ(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
  ) async {
    final fromQuery = options.queryParameters['q'];
    if (fromQuery is String && fromQuery.isNotEmpty) {
      return fromQuery;
    }

    final data = options.data;
    if (data is String) {
      return _qFromBody(data);
    }
    if (data is List<int>) {
      return _qFromBody(utf8.decode(data));
    }

    if (requestStream != null) {
      final chunks = <int>[];
      await for (final chunk in requestStream) {
        chunks.addAll(chunk);
      }
      return _qFromBody(utf8.decode(chunks));
    }

    return '';
  }

  String _qFromBody(String body) {
    if (!body.startsWith('q=')) {
      return '';
    }
    return Uri.decodeComponent(body.substring(2));
  }

  @override
  void close({bool force = false}) {}
}

String singleLineResponse(String translated) {
  return '[[["$translated","x"]],null,"zh-CN"]';
}

void main() {
  test('translates a newline-batched request in one call', () async {
    final adapter = _FakeAdapter(
      (_) => const FakeResponse(
        '[[["line one\\n","x"],["line two","y"]],null,"zh-CN"]',
      ),
    );

    final service = GoogleTranslateService(
      dio: Dio()..httpClientAdapter = adapter,
    );

    final result = await service.translateParagraphs(
      ['AAA', 'BBB'],
      targetLanguage: 'en',
    );

    expect(result, ['line one', 'line two']);
    expect(adapter.queries, ['AAA\nBBB']);
    expect(adapter.methods, everyElement('POST'));
  });

  test('falls back to per-paragraph when line count differs',
      () async {
    final adapter = _FakeAdapter(
      (q) => q.contains('\n')
          ? const FakeResponse('[[["merged","x"]],null,"zh-CN"]')
          : FakeResponse(singleLineResponse('T($q)')),
    );

    final service = GoogleTranslateService(
      dio: Dio()..httpClientAdapter = adapter,
    );

    final result = await service.translateParagraphs(
      ['AAA', 'BBB'],
      targetLanguage: 'en',
    );

    expect(result, ['T(AAA)', 'T(BBB)']);
    expect(adapter.queries, ['AAA\nBBB', 'AAA', 'BBB']);
  });

  test('splits oversized chapters into batches', () async {
    final adapter = _FakeAdapter(
      (q) => FakeResponse(singleLineResponse('T')),
    );

    final service = GoogleTranslateService(
      dio: Dio()..httpClientAdapter = adapter,
    );

    final result = await service.translateParagraphs(
      ['a' * 3000, 'b' * 3000],
      targetLanguage: 'en',
    );

    expect(result, ['T', 'T']);
    expect(adapter.queries.length, 2);
  });

  test('returns empty list for no paragraphs', () async {
    final adapter = _FakeAdapter(
      (_) => const FakeResponse('[]'),
    );

    final service = GoogleTranslateService(
      dio: Dio()..httpClientAdapter = adapter,
    );

    final result = await service.translateParagraphs(
      [],
      targetLanguage: 'en',
    );

    expect(result, isEmpty);
    expect(adapter.queries, isEmpty);
  });

  test('maps HTTP errors to a friendly message', () async {
    final adapter = _FakeAdapter(
      (_) => const FakeResponse('{}', status: 500),
    );

    final service = GoogleTranslateService(
      dio: Dio()..httpClientAdapter = adapter,
      maxAttempts: 1,
    );

    await expectLater(
      service.translateParagraphs(['AAA'], targetLanguage: 'en'),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('HTTP 500'),
        ),
      ),
    );
  });

  test('retries a rate-limited request and succeeds', () async {
    var calls = 0;
    final adapter = _FakeAdapter(
      (_) => ++calls == 1
          ? const FakeResponse('{}', status: 429)
          : FakeResponse(singleLineResponse('T(AAA)')),
    );

    final service = GoogleTranslateService(
      dio: Dio()..httpClientAdapter = adapter,
      retryBaseDelay: Duration.zero,
    );

    final result = await service.translateParagraphs(
      ['AAA'],
      targetLanguage: 'en',
    );

    expect(result, ['T(AAA)']);
    expect(calls, 2);
  });

  test('gives up after maxAttempts with a rate-limit message', () async {
    final adapter = _FakeAdapter(
      (_) => const FakeResponse('{}', status: 429),
    );

    final service = GoogleTranslateService(
      dio: Dio()..httpClientAdapter = adapter,
      maxAttempts: 2,
      retryBaseDelay: Duration.zero,
    );

    await expectLater(
      service.translateParagraphs(['AAA'], targetLanguage: 'en'),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('rate limited'),
        ),
      ),
    );
    expect(adapter.queries.length, 2);
  });

  test('rejects unexpected response shapes', () async {
    final adapter = _FakeAdapter(
      (_) => const FakeResponse('[]'),
    );

    final service = GoogleTranslateService(
      dio: Dio()..httpClientAdapter = adapter,
    );

    await expectLater(
      service.translateParagraphs(['AAA'], targetLanguage: 'en'),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Unexpected response'),
        ),
      ),
    );
  });
}
