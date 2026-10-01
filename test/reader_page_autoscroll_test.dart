import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/network/dio_client.dart';
import 'package:novel_reader/features/reader/domain/services/text_to_speech.dart';
import 'package:novel_reader/features/reader/presentation/pages/reader_page.dart';
import 'package:novel_reader/features/reader/presentation/providers/reader_tts_controller.dart';
import 'package:novel_reader/features/scraper/data/repositories/scraper_repository.dart';
import 'package:novel_reader/features/scraper/data/services/generic_novel_adapter.dart';
import 'package:novel_reader/features/scraper/domain/models/extracted_chapter.dart';
import 'package:novel_reader/features/scraper/presentation/providers/scraper_providers.dart';

class _FakeTts implements TextToSpeech {
  int stopCalls = 0;

  @override
  Future<void> setLanguage(String language) async {}

  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  Future<void> setVoice(String name, String locale) async {}

  @override
  Future<List<TtsVoice>> getVoices() async => const [];

  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  void onCompletion(void Function() handler) {}

  @override
  void onCancel(void Function() handler) {}

  @override
  void onError(void Function(dynamic message) handler) {}
}

class _FakeScraper extends ScraperRepository {
  _FakeScraper()
      : super(
          dioClient: DioClient(),
          adapter: GenericNovelAdapter(),
        );

  final Map<String, ExtractedChapter> chapters =
      <String, ExtractedChapter>{};
  final List<String> requests = <String>[];

  @override
  Future<ExtractedChapter> extractChapter(String url) async {
    requests.add(url);

    final chapter = chapters[url];
    if (chapter == null) {
      throw Exception('No chapter for $url');
    }

    return chapter;
  }
}

ExtractedChapter makeChapter(
  String name, {
  String? nextChapterUrl,
  String? previousChapterUrl,
}) {
  return ExtractedChapter(
    title: 'Chapter $name',
    paragraphs: List<String>.generate(
      60,
      (i) =>
          'Paragraph $i of chapter $name. '
          'Lorem ipsum dolor sit amet, consectetur adipiscing elit, '
          'sed do eiusmod tempor incididunt ut labore et dolore. ',
    ),
    url: 'https://example.com/$name',
    nextChapterUrl: nextChapterUrl,
    previousChapterUrl: previousChapterUrl,
  );
}

double scrollPixels(WidgetTester tester) {
  final scrollable =
      tester.state<ScrollableState>(find.byType(Scrollable));
  return scrollable.position.pixels;
}

void main() {
  late _FakeTts fakeTts;
  late _FakeScraper scraper;

  Widget build(ExtractedChapter chapter) {
    return ProviderScope(
      overrides: [
        scraperRepositoryProvider.overrideWithValue(scraper),
        readerTtsControllerProvider.overrideWith(
          (ref) => ReaderTtsController(tts: fakeTts),
        ),
      ],
      child: MaterialApp(
        home: ReaderPage(chapter: chapter),
      ),
    );
  }

  setUp(() {
    fakeTts = _FakeTts();
    scraper = _FakeScraper();
  });

  testWidgets(
    'follows TTS to a distant paragraph and resets on chapter change',
    (tester) async {
      final chapter1 = makeChapter(
        'one',
        nextChapterUrl: 'https://example.com/two',
      );
      final chapter2 = makeChapter('two');
      scraper.chapters[chapter1.url] = chapter1;
      scraper.chapters[chapter2.url] = chapter2;

      await tester.pumpWidget(build(chapter1));
      await tester.pump();
      await tester.pump();

      expect(scrollPixels(tester), 0);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ReaderPage)),
      );
      final tts = container.read(readerTtsControllerProvider.notifier);

      await tts.play(chapter1.paragraphs, startIndex: 45);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(scrollPixels(tester), greaterThan(0));

      await tester.tap(find.byTooltip('Next chapter'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(scraper.requests, ['https://example.com/two']);
      expect(scrollPixels(tester), 0);
    },
  );

  testWidgets(
    'keeps position when the active paragraph is visible',
    (tester) async {
      final chapter = makeChapter('one');
      scraper.chapters[chapter.url] = chapter;

      await tester.pumpWidget(build(chapter));
      await tester.pump();
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ReaderPage)),
      );
      final tts = container.read(readerTtsControllerProvider.notifier);

      await tts.play(chapter.paragraphs, startIndex: 1);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(scrollPixels(tester), 0);
    },
  );

  testWidgets(
    'does not scroll when auto-scroll is toggled off',
    (tester) async {
      final chapter = makeChapter('one');
      scraper.chapters[chapter.url] = chapter;

      await tester.pumpWidget(build(chapter));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip('Auto-scroll'));
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ReaderPage)),
      );
      final tts = container.read(readerTtsControllerProvider.notifier);

      await tts.play(chapter.paragraphs, startIndex: 45);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(scrollPixels(tester), 0);
    },
  );
}
