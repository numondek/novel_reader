import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/network/dio_client.dart';
import 'package:novel_reader/features/novels/domain/models/read_novel.dart';
import 'package:novel_reader/features/novels/presentation/providers/read_novels_provider.dart';
import 'package:novel_reader/features/reader/presentation/pages/reader_page.dart';
import 'package:novel_reader/features/reader/presentation/providers/reader_controller.dart';
import 'package:novel_reader/features/scraper/data/repositories/scraper_repository.dart';
import 'package:novel_reader/features/scraper/data/services/generic_novel_adapter.dart';
import 'package:novel_reader/features/scraper/domain/models/extracted_chapter.dart';
import 'package:novel_reader/features/scraper/presentation/providers/scraper_providers.dart';

class _SeededReadNovels extends ReadNovelsController {
  _SeededReadNovels(this.seed);

  final List<ReadNovel> seed;

  @override
  Future<List<ReadNovel>> build() async => seed;
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

final ExtractedChapter longChapter = ExtractedChapter(
  title: 'Chapter 1',
  paragraphs: List.generate(
    30,
    (index) => 'Paragraph $index: '
        'lorem ipsum dolor sit amet consectetur adipiscing elit '
        'sed do eiusmod tempor incididunt ut labore et dolore.',
  ),
  url: 'https://site.com/n/ch-1',
  novelTitle: 'Nova',
);

ReadNovel savedEntry({int paragraphIndex = 0}) {
  return ReadNovel(
    key: 'novel:site.com:Nova',
    url: 'https://site.com/n/ch-1',
    novelTitle: 'Nova',
    chapterTitle: 'Chapter 1',
    paragraphIndex: paragraphIndex,
    readAt: DateTime.now(),
  );
}

Widget buildApp({required List<ReadNovel> seed}) {
  return ProviderScope(
    overrides: [
      readNovelsProvider.overrideWith(() => _SeededReadNovels(seed)),
      scraperRepositoryProvider.overrideWithValue(_FakeScraper()),
    ],
    child: MaterialApp(
      home: ReaderPage(chapter: longChapter),
    ),
  );
}

double scrollPixels(WidgetTester tester) {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  return scrollable.position.pixels;
}

void main() {
  testWidgets(
    'reopening a saved chapter resumes at the stored paragraph',
    (tester) async {
      await tester.pumpWidget(
        buildApp(seed: [savedEntry(paragraphIndex: 10)]),
      );

      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      expect(scrollPixels(tester), greaterThan(0));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ReaderPage)),
      );
      final state = container.read(readerControllerProvider);
      expect(state.activeParagraph, 10);
    },
  );

  testWidgets(
    'scrolling saves the paragraph being read',
    (tester) async {
      await tester.pumpWidget(buildApp(seed: [savedEntry()]));
      await tester.pumpAndSettle();

      expect(scrollPixels(tester), 0);

      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -2500),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ReaderPage)),
      );
      final entries = await container.read(readNovelsProvider.future);

      expect(entries.single.paragraphIndex, greaterThan(0));
    },
  );
}
