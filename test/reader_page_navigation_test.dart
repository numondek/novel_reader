import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/network/dio_client.dart';
import 'package:novel_reader/features/reader/presentation/pages/reader_page.dart';
import 'package:novel_reader/features/scraper/data/repositories/scraper_repository.dart';
import 'package:novel_reader/features/scraper/data/services/generic_novel_adapter.dart';
import 'package:novel_reader/features/scraper/domain/models/extracted_chapter.dart';
import 'package:novel_reader/features/scraper/presentation/providers/scraper_providers.dart';

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

Finder _button(String tooltip) => find.ancestor(
      of: find.byTooltip(tooltip),
      matching: find.byType(IconButton),
    );

Widget _buildApp(_FakeScraper scraper, ExtractedChapter chapter) {
  return ProviderScope(
    overrides: [
      scraperRepositoryProvider.overrideWithValue(scraper),
    ],
    child: MaterialApp(
      home: ReaderPage(chapter: chapter),
    ),
  );
}

const chapterOne = ExtractedChapter(
  title: 'One',
  paragraphs: ['First chapter text'],
  url: 'https://example.com/1',
  nextChapterUrl: 'https://example.com/2',
  previousChapterUrl: 'https://example.com/0',
);

const chapterTwo = ExtractedChapter(
  title: 'Two',
  paragraphs: ['Second chapter text'],
  url: 'https://example.com/2',
  previousChapterUrl: 'https://example.com/1',
);

void main() {
  testWidgets(
    'tapping next fetches and renders the next chapter',
    (tester) async {
      final scraper = _FakeScraper()
        ..chapters['https://example.com/1'] = chapterOne
        ..chapters['https://example.com/2'] = chapterTwo;

      await tester.pumpWidget(_buildApp(scraper, chapterOne));
      await tester.pump();
      await tester.pump();

      expect(find.text('One'), findsWidgets);
      expect(find.text('Second chapter text'), findsNothing);

      final nextButton = _button('Next chapter');
      expect(
        tester.widget<IconButton>(nextButton).onPressed,
        isNotNull,
      );

      await tester.tap(nextButton);
      await tester.pump();
      await tester.pump();

      expect(scraper.requests, ['https://example.com/2']);
      expect(find.text('Second chapter text'), findsOneWidget);

      final previousButton = _button('Previous chapter');
      expect(
        tester.widget<IconButton>(previousButton).onPressed,
        isNotNull,
      );

      await tester.tap(previousButton);
      await tester.pump();
      await tester.pump();

      expect(
        scraper.requests,
        ['https://example.com/2', 'https://example.com/1'],
      );
      expect(find.text('First chapter text'), findsOneWidget);
    },
  );

  testWidgets(
    'buttons are disabled when the chapter has no links',
    (tester) async {
      final scraper = _FakeScraper()
        ..chapters['https://example.com/solo'] = const ExtractedChapter(
          title: 'Solo',
          paragraphs: ['Only chapter'],
          url: 'https://example.com/solo',
        );

      await tester.pumpWidget(
        _buildApp(scraper, const ExtractedChapter(
          title: 'Solo',
          paragraphs: ['Only chapter'],
          url: 'https://example.com/solo',
        )),
      );
      await tester.pump();
      await tester.pump();

      expect(
        tester.widget<IconButton>(_button('Next chapter')).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(_button('Previous chapter'))
            .onPressed,
        isNull,
      );
    },
  );
}
