import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/network/dio_client.dart';
import 'package:novel_reader/features/reader/presentation/providers/reader_controller.dart';
import 'package:novel_reader/features/scraper/data/repositories/scraper_repository.dart';
import 'package:novel_reader/features/scraper/data/services/generic_novel_adapter.dart';
import 'package:novel_reader/features/scraper/domain/models/extracted_chapter.dart';
import 'package:novel_reader/features/translation/domain/services/translation_service.dart';

class _NoopTranslator implements TranslationService {
  @override
  Future<List<String>> translateParagraphs(
    List<String> paragraphs, {
    required String targetLanguage,
  }) async {
    return paragraphs;
  }
}

class _FakeScraper extends ScraperRepository {
  _FakeScraper()
      : super(
          dioClient: DioClient(),
          adapter: GenericNovelAdapter(),
        );

  final List<String> requests = <String>[];
  Completer<void>? gate;
  Object? failure;

  @override
  Future<ExtractedChapter> extractChapter(String url) async {
    requests.add(url);

    final pending = gate;
    if (pending != null) {
      await pending.future;
    }

    final error = failure;
    if (error != null) {
      throw error;
    }

    return ExtractedChapter(
      title: 'Chapter at $url',
      paragraphs: ['Paragraph at $url'],
      url: url,
    );
  }
}

ExtractedChapter startChapter() => const ExtractedChapter(
      title: 'One',
      paragraphs: ['First paragraph'],
      url: 'https://example.com/1',
      nextChapterUrl: 'https://example.com/2',
    );

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('nextChapter fetches and opens the next chapter', () async {
    final scraper = _FakeScraper();
    final controller = ReaderController(
      translator: _NoopTranslator(),
      scraper: scraper,
    );
    controller.openChapter(startChapter());

    await controller.nextChapter();

    expect(scraper.requests, ['https://example.com/2']);
    expect(controller.state.chapter?.url, 'https://example.com/2');
    expect(controller.state.chapter?.paragraphs, [
      'Paragraph at https://example.com/2',
    ]);
    expect(controller.state.isLoading, isFalse);
  });

  test('previousChapter fetches the previous chapter', () async {
    final scraper = _FakeScraper();
    final controller = ReaderController(
      translator: _NoopTranslator(),
      scraper: scraper,
    );
    controller.openChapter(const ExtractedChapter(
      title: 'Two',
      paragraphs: ['p'],
      url: 'https://example.com/2',
      previousChapterUrl: 'https://example.com/1',
    ));

    await controller.previousChapter();

    expect(scraper.requests, ['https://example.com/1']);
    expect(controller.state.chapter?.url, 'https://example.com/1');
  });

  test('navigation is a no-op without chapter urls', () async {
    final scraper = _FakeScraper();
    final controller = ReaderController(
      translator: _NoopTranslator(),
      scraper: scraper,
    );
    controller.openChapter(const ExtractedChapter(
      title: 'Solo',
      paragraphs: ['p'],
      url: 'https://example.com/solo',
    ));

    await controller.nextChapter();
    await controller.previousChapter();

    expect(scraper.requests, isEmpty);
    expect(controller.state.chapter?.url, 'https://example.com/solo');
  });

  test('isLoading is set while fetching the next chapter', () async {
    final scraper = _FakeScraper()..gate = Completer<void>();
    final controller = ReaderController(
      translator: _NoopTranslator(),
      scraper: scraper,
    );
    controller.openChapter(startChapter());

    final future = controller.nextChapter();

    expect(controller.state.isLoading, isTrue);

    scraper.gate!.complete();
    await future;

    expect(controller.state.isLoading, isFalse);
    expect(controller.state.chapter?.url, 'https://example.com/2');
  });

  test('failed navigation keeps the chapter and surfaces an error',
      () async {
    final scraper = _FakeScraper()..failure = Exception('network down');
    final controller = ReaderController(
      translator: _NoopTranslator(),
      scraper: scraper,
    );
    controller.openChapter(startChapter());

    await controller.nextChapter();

    expect(controller.state.chapter?.url, 'https://example.com/1');
    expect(controller.state.chapter?.paragraphs, ['First paragraph']);
    expect(controller.state.isLoading, isFalse);
    expect(controller.state.error, contains('network down'));
  });
}
