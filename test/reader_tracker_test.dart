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
  Future<void> stop() async {}

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

  @override
  Future<ExtractedChapter> extractChapter(String url) async {
    throw UnimplementedError('not needed in this test');
  }
}

final ExtractedChapter trackedChapter = ExtractedChapter(
  title: 'Chapter 1',
  paragraphs: List.generate(
    60,
    (index) => 'Paragraph $index: '
        'lorem ipsum dolor sit amet consectetur adipiscing elit '
        'sed do eiusmod tempor incididunt ut labore et dolore.',
  ),
  url: 'https://site.com/n/ch-1',
);

Widget buildApp() {
  return ProviderScope(
    overrides: [
      scraperRepositoryProvider.overrideWithValue(_FakeScraper()),
      readerTtsControllerProvider.overrideWith(
        (ref) => ReaderTtsController(tts: _FakeTts()),
      ),
    ],
    child: MaterialApp(
      home: ReaderPage(chapter: trackedChapter),
    ),
  );
}

ScrollableState scrollState(WidgetTester tester) {
  return tester.state<ScrollableState>(find.byType(Scrollable).first);
}

/// Portion of the tracker line that is filled (read) versus the
/// full line width (the whole chapter).
double fillFraction(WidgetTester tester) {
  final fill = tester.getSize(find.byKey(const ValueKey('tracker-fill')));
  final track = tester.getSize(find.byKey(const ValueKey('tracker-track')));
  return fill.width / track.width;
}

void main() {
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();
  }

  testWidgets('tracker line starts empty and is labelled', (tester) async {
    final handle = tester.ensureSemantics();

    await pumpPage(tester);

    expect(find.bySemanticsLabel('Reading progress'), findsOneWidget);
    expect(fillFraction(tester), 0);

    handle.dispose();
  });

  testWidgets('filling the viewport marks the chapter as read',
      (tester) async {
    await pumpPage(tester);

    final scrollable = scrollState(tester);
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();

    expect(fillFraction(tester), closeTo(1.0, 0.01));

    scrollable.position.jumpTo(0);
    await tester.pump();

    expect(fillFraction(tester), 0);
  });

  testWidgets('narration pins the line to the paragraph being read',
      (tester) async {
    await pumpPage(tester);

    // Keep the viewport still so only narration can move the line.
    await tester.tap(find.byTooltip('Auto-scroll'));
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReaderPage)),
    );
    final tts = container.read(readerTtsControllerProvider.notifier);

    await tts.play(trackedChapter.paragraphs, startIndex: 45);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(scrollState(tester).position.pixels, 0);
    expect(fillFraction(tester), closeTo(46 / 60, 0.01));
  });

  testWidgets('stopping narration falls back to the scroll position',
      (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byTooltip('Auto-scroll'));
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReaderPage)),
    );
    final tts = container.read(readerTtsControllerProvider.notifier);

    await tts.play(trackedChapter.paragraphs, startIndex: 45);
    await tester.pump();
    await tester.pumpAndSettle();

    await tts.stopAll();
    await tester.pump();

    expect(fillFraction(tester), 0);
  });
}
