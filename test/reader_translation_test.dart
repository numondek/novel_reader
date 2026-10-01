import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/network/dio_client.dart';
import 'package:novel_reader/features/novels/domain/models/chapter.dart';
import 'package:novel_reader/features/reader/presentation/providers/reader_controller.dart';
import 'package:novel_reader/features/scraper/data/repositories/scraper_repository.dart';
import 'package:novel_reader/features/scraper/data/services/generic_novel_adapter.dart';
import 'package:novel_reader/features/scraper/domain/models/extracted_chapter.dart';
import 'package:novel_reader/features/translation/domain/services/translation_service.dart';

class _FakeTranslator implements TranslationService {
  int calls = 0;

  @override
  Future<List<String>> translateParagraphs(
    List<String> paragraphs, {
    required String targetLanguage,
  }) async {
    calls += 1;
    return paragraphs.map((paragraph) => 'EN: $paragraph').toList();
  }
}

class _ThrowingTranslator implements TranslationService {
  @override
  Future<List<String>> translateParagraphs(
    List<String> paragraphs, {
    required String targetLanguage,
  }) async {
    throw Exception('Translation failed. Check your connection.');
  }
}

class _FakeScraper extends ScraperRepository {
  _FakeScraper()
      : super(
          dioClient: DioClient(),
          adapter: GenericNovelAdapter(),
        );

  @override
  Future<ExtractedChapter> extractChapter(String url) async {
    return ExtractedChapter(
      title: 'Fetched',
      paragraphs: ['Fetched paragraph'],
      url: url,
    );
  }
}

ExtractedChapter cjkChapter() => const ExtractedChapter(
      title: '第一章 十小圣之首',
      paragraphs: ['通天妖圣现身，妖庭天命另有其人'],
      url: 'https://example.com/chapter-1',
    );

ExtractedChapter englishChapter() => const ExtractedChapter(
      title: 'Chapter 1: The Beginning',
      paragraphs: ['The hero walked into the misty valley.'],
      url: 'https://example.com/chapter-2',
    );

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('CJK chapter auto-translates on open', () async {
    final translator = _FakeTranslator();
    final controller = ReaderController(
      translator: translator,
      scraper: _FakeScraper(),
    );

    controller.openChapter(cjkChapter());
    await flush();

    final state = controller.state;
    expect(translator.calls, 2);
    expect(state.isTranslating, isFalse);
    expect(state.translatedTitle, 'EN: 第一章 十小圣之首');
    expect(state.translatedParagraphs, [
      'EN: 通天妖圣现身，妖庭天命另有其人',
    ]);
    expect(state.chapter?.status, ChapterStatus.ready);
  });

  test('English chapter does not auto-translate', () async {
    final translator = _FakeTranslator();
    final controller = ReaderController(
      translator: translator,
      scraper: _FakeScraper(),
    );

    controller.openChapter(englishChapter());
    await flush();

    expect(translator.calls, 0);
    expect(controller.state.translatedParagraphs, isNull);
    expect(controller.state.chapter?.status, ChapterStatus.reading);
  });

  test('toggle translates an original chapter', () async {
    final translator = _FakeTranslator();
    final controller = ReaderController(
      translator: translator,
      scraper: _FakeScraper(),
    );

    controller.openChapter(englishChapter());
    await flush();

    controller.toggleTranslation();
    await flush();

    expect(translator.calls, 2);
    expect(controller.state.translatedParagraphs, isNotNull);
    expect(controller.state.chapter?.status, ChapterStatus.ready);
  });

  test('toggle clears translation back to the original', () async {
    final translator = _FakeTranslator();
    final controller = ReaderController(
      translator: translator,
      scraper: _FakeScraper(),
    );

    controller.openChapter(cjkChapter());
    await flush();
    expect(controller.state.translatedParagraphs, isNotNull);

    controller.toggleTranslation();
    await flush();

    expect(controller.state.translatedParagraphs, isNull);
    expect(controller.state.translatedTitle, isNull);
    expect(controller.state.chapter?.status, ChapterStatus.reading);
  });

  test('translation failure sets a friendly error', () async {
    final controller = ReaderController(
      translator: _ThrowingTranslator(),
      scraper: _FakeScraper(),
    );

    controller.openChapter(cjkChapter());
    await flush();

    final state = controller.state;
    expect(state.isTranslating, isFalse);
    expect(state.error, contains('Translation failed'));
    expect(state.chapter?.status, ChapterStatus.reading);
    expect(state.translatedParagraphs, isNull);
  });
}
