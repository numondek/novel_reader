import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/network/dio_client.dart';
import 'package:novel_reader/features/novels/domain/models/read_novel.dart';
import 'package:novel_reader/features/novels/presentation/providers/read_novels_provider.dart';
import 'package:novel_reader/features/prefetch/presentation/pages/prefetch_page.dart';
import 'package:novel_reader/features/prefetch/presentation/providers/offline_chapter_store_provider.dart';
import 'package:novel_reader/features/scraper/data/repositories/scraper_repository.dart';
import 'package:novel_reader/features/scraper/data/services/generic_novel_adapter.dart';
import 'package:novel_reader/features/scraper/domain/models/extracted_chapter.dart';
import 'package:novel_reader/features/scraper/domain/models/manhwa_series.dart';
import 'package:novel_reader/features/scraper/domain/services/offline_chapter_store.dart';
import 'package:novel_reader/features/scraper/presentation/providers/manhwa_shelf_provider.dart';
import 'package:novel_reader/features/scraper/presentation/providers/scraper_providers.dart';

class _SeededReadNovels extends ReadNovelsController {
  _SeededReadNovels(this.seed);

  final List<ReadNovel> seed;

  @override
  Future<List<ReadNovel>> build() async => seed;
}

class _SeededShelf extends ManhwaSeriesController {
  _SeededShelf(this.seed);

  final List<ManhwaSeries> seed;

  @override
  Future<List<ManhwaSeries>> build() async => seed;
}

class _FakeScraper extends ScraperRepository {
  _FakeScraper()
    : super(dioClient: DioClient(), adapter: GenericNovelAdapter());

  final Map<String, ExtractedChapter> chapters = <String, ExtractedChapter>{};
  final List<String> requests = <String>[];
  int? failOnRequest;
  Completer<void>? gate;

  @override
  Future<ExtractedChapter> extractChapter(String url) async {
    final pending = gate;
    if (pending != null) await pending.future;

    requests.add(url);

    final failingAt = failOnRequest;
    if (failingAt != null && requests.length >= failingAt) {
      throw Exception('Network is down');
    }

    final chapter = chapters[url];
    if (chapter == null) {
      throw Exception('No chapter for $url');
    }

    return chapter;
  }
}

class _FakeStore implements OfflineChapterStore {
  final Map<String, List<ExtractedChapter>> novels =
      <String, List<ExtractedChapter>>{};
  final Map<String, ExtractedChapter> urls = <String, ExtractedChapter>{};

  @override
  Future<List<ExtractedChapter>> load(String novelKey) async {
    final saved = novels[novelKey];
    if (saved == null) return const [];
    return List<ExtractedChapter>.of(saved);
  }

  @override
  Future<int> count(String novelKey) async => novels[novelKey]?.length ?? 0;

  @override
  Future<void> save(String novelKey, ExtractedChapter chapter) async {
    urls[chapter.url] = chapter;
    (novels[novelKey] ??= <ExtractedChapter>[]).add(chapter);
  }

  @override
  Future<void> remove(String novelKey) async {
    for (final chapter
        in novels.remove(novelKey) ?? const <ExtractedChapter>[]) {
      urls.remove(chapter.url);
    }
  }

  @override
  Future<ExtractedChapter?> find(String url) async => urls[url];
}

final ReadNovel novel = ReadNovel(
  key: 'novel:example.com:Demo',
  url: 'https://example.com/1',
  novelTitle: 'Demo',
  chapterTitle: 'Chapter 1',
  readAt: DateTime(2026),
);

/// The same novel entry as if the reader were at [number].
ReadNovel readingAt(int number) {
  return ReadNovel(
    key: novel.key,
    url: 'https://example.com/$number',
    novelTitle: 'Demo',
    chapterTitle: 'Chapter $number',
    readAt: DateTime(2026),
  );
}

_FakeScraper _chain({int last = 50}) {
  final scraper = _FakeScraper();

  for (var number = 1; number <= last; number++) {
    scraper.chapters['https://example.com/$number'] = ExtractedChapter(
      title: 'Chapter $number',
      paragraphs: <String>['Text $number'],
      url: 'https://example.com/$number',
      nextChapterUrl:
          number < last ? 'https://example.com/${number + 1}' : null,
    );
  }

  return scraper;
}

Widget _buildApp({
  required List<ReadNovel> novels,
  required _FakeScraper scraper,
  required _FakeStore store,
  List<ManhwaSeries> shelf = const [],
}) {
  return ProviderScope(
    overrides: [
      readNovelsProvider.overrideWith(() => _SeededReadNovels(novels)),
      manhwaSeriesProvider.overrideWith(() => _SeededShelf(shelf)),
      scraperRepositoryProvider.overrideWithValue(scraper),
      offlineChapterStoreProvider.overrideWithValue(store),
    ],
    child: const MaterialApp(home: PrefetchPage()),
  );
}

void main() {
  testWidgets('without read novels the page offers a hint', (tester) async {
    await tester.pumpWidget(
      _buildApp(novels: const [], scraper: _FakeScraper(), store: _FakeStore()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing to prefetch yet'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('the first tap saves ten chapters', (tester) async {
    final scraper = _chain();
    final store = _FakeStore();

    await tester.pumpWidget(
      _buildApp(novels: [novel], scraper: scraper, store: store),
    );
    await tester.pumpAndSettle();

    expect(find.text('Save 10 chapters'), findsOneWidget);
    expect(find.text('No chapters saved yet'), findsOneWidget);

    await tester.tap(find.text('Save 10 chapters'));
    await tester.pumpAndSettle();

    expect(find.text('Get next 10 chapters'), findsOneWidget);
    expect(find.text('10 chapters saved offline'), findsOneWidget);
    expect(find.text('Chapter 1'), findsOneWidget);
    expect(store.novels[novel.key], hasLength(10));
    expect(scraper.requests, hasLength(10));
  });

  testWidgets('the next button keeps saving', (tester) async {
    final scraper = _chain();
    final store = _FakeStore();

    await tester.pumpWidget(
      _buildApp(novels: [novel], scraper: scraper, store: store),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save 10 chapters'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get next 10 chapters'));
    await tester.pumpAndSettle();

    expect(find.text('20 chapters saved offline'), findsOneWidget);
    expect(store.novels[novel.key], hasLength(20));
    expect(scraper.requests[10], 'https://example.com/11');
  });

  testWidgets('progress shows while a batch is saving', (tester) async {
    final scraper = _chain()..gate = Completer<void>();
    final store = _FakeStore();

    await tester.pumpWidget(
      _buildApp(novels: [novel], scraper: scraper, store: store),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save 10 chapters'));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Saving…'), findsOneWidget);
    expect(find.text('Saved 0 of 10'), findsOneWidget);

    scraper.gate!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('10 chapters saved offline'), findsOneWidget);
  });

  testWidgets('a finished novel replaces the button with a note', (
    tester,
  ) async {
    final scraper = _chain(last: 4);
    final store = _FakeStore();

    await tester.pumpWidget(
      _buildApp(novels: [novel], scraper: scraper, store: store),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save 10 chapters'));
    await tester.pumpAndSettle();

    expect(find.text('Every chapter is saved.'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(store.novels[novel.key], hasLength(4));
  });

  testWidgets('a fetch failure is reported with a snack bar', (tester) async {
    final scraper = _chain()..failOnRequest = 1;
    final store = _FakeStore();

    await tester.pumpWidget(
      _buildApp(novels: [novel], scraper: scraper, store: store),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save 10 chapters'));
    await tester.pumpAndSettle();

    expect(find.text('Network is down'), findsOneWidget);
    expect(find.text('Save 10 chapters'), findsOneWidget);
    expect(store.novels[novel.key], isNull);
  });

  testWidgets('the order button reverses the saved chapters', (tester) async {
    final store =
        _FakeStore()
          ..novels[novel.key] = [
            ExtractedChapter(
              title: 'Chapter 1',
              paragraphs: const ['Text 1'],
              url: 'https://example.com/1',
            ),
            ExtractedChapter(
              title: 'Chapter 2',
              paragraphs: const ['Text 2'],
              url: 'https://example.com/2',
            ),
            ExtractedChapter(
              title: 'Chapter 3',
              paragraphs: const ['Text 3'],
              url: 'https://example.com/3',
            ),
          ];

    await tester.pumpWidget(
      _buildApp(novels: [novel], scraper: _FakeScraper(), store: store),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 chapters saved offline'), findsOneWidget);

    // Saved chapters start in reading order.
    expect(find.byTooltip('Sort descending'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Chapter 1')).dy,
      lessThan(tester.getTopLeft(find.text('Chapter 3')).dy),
    );

    await tester.tap(find.byTooltip('Sort descending'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Sort ascending'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Chapter 3')).dy,
      lessThan(tester.getTopLeft(find.text('Chapter 1')).dy),
    );
  });

  testWidgets('saving starts from the chapter being read', (tester) async {
    final scraper = _chain();
    final store =
        _FakeStore()
          ..novels[novel.key] = [
            ExtractedChapter(
              title: 'Chapter 1',
              paragraphs: const ['Text 1'],
              url: 'https://example.com/1',
              nextChapterUrl: 'https://example.com/2',
            ),
            ExtractedChapter(
              title: 'Chapter 2',
              paragraphs: const ['Text 2'],
              url: 'https://example.com/2',
              nextChapterUrl: 'https://example.com/3',
            ),
            ExtractedChapter(
              title: 'Chapter 3',
              paragraphs: const ['Text 3'],
              url: 'https://example.com/3',
              nextChapterUrl: 'https://example.com/4',
            ),
          ];

    await tester.pumpWidget(
      _buildApp(novels: [readingAt(20)], scraper: scraper, store: store),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 chapters saved offline'), findsOneWidget);

    await tester.tap(find.text('Get next 10 chapters'));
    await tester.pumpAndSettle();

    expect(scraper.requests.first, 'https://example.com/20');
    expect(scraper.requests, hasLength(10));
    expect(find.text('13 chapters saved offline'), findsOneWidget);
    expect(find.text('Chapter 20'), findsOneWidget);
  });

  testWidgets('a manhwa history leaves this list to the shelf', (tester) async {
    final history = [
      ReadNovel(
        key: 'manhwa:example.com/manga/grid',
        url: 'https://example.com/manga/grid/chapter-1',
        novelTitle: 'Grid Demo',
        chapterTitle: 'Chapter 1',
        readAt: DateTime(2026),
      ),
      ReadNovel(
        key: 'url:example.com:manga',
        url: 'https://example.com/manga/other/chapter-1',
        chapterTitle: 'Chapter 1 - Panel',
        readAt: DateTime(2026),
      ),
    ];

    final shelf = [
      ManhwaSeries(
        novelKey: 'manhwa:example.com/manga/grid',
        title: 'Grid Demo',
        sourceUrl: 'https://example.com/manga/grid',
        openedAt: DateTime(2026),
      ),
      ManhwaSeries(
        novelKey: 'manhwa:example.com/manga/other',
        title: 'Grid Other',
        sourceUrl: 'https://example.com/manga/other',
        openedAt: DateTime(2026),
      ),
    ];

    await tester.pumpWidget(
      _buildApp(
        novels: history,
        shelf: shelf,
        scraper: _FakeScraper(),
        store: _FakeStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing to prefetch yet'), findsOneWidget);
    expect(find.text('Grid Demo'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

  testWidgets('saved chapters say whether they were read', (tester) async {
    final store =
        _FakeStore()
          ..novels[novel.key] = [
            ExtractedChapter(
              title: 'Chapter 1',
              paragraphs: const ['Text 1'],
              url: 'https://example.com/1',
            ),
            ExtractedChapter(
              title: 'Chapter 2',
              paragraphs: const ['Text 2'],
              url: 'https://example.com/2',
            ),
            ExtractedChapter(
              title: 'Chapter 3',
              paragraphs: const ['Text 3'],
              url: 'https://example.com/3',
            ),
          ];

    final reading = ReadNovel(
      key: novel.key,
      url: 'https://example.com/2',
      novelTitle: 'Demo',
      chapterTitle: 'Chapter 2',
      paragraphIndex: 4,
      paragraphCount: 11,
      chapterProgress: const {
        'https://example.com/1': [2, 3],
        'https://example.com/2': [4, 11],
      },
      readAt: DateTime(2026),
    );

    await tester.pumpWidget(
      _buildApp(novels: [reading], scraper: _FakeScraper(), store: store),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 chapters saved offline'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    expect(find.text('100% read'), findsOneWidget);
    expect(find.text('40% read'), findsOneWidget);
  });

  testWidgets('a saved chapter title without a number shows it', (
    tester,
  ) async {
    final store =
        _FakeStore()
          ..novels[novel.key] = [
            ExtractedChapter(
              title: 'The duel',
              paragraphs: const ['Text'],
              url: 'https://example.com/7',
            ),
          ];

    await tester.pumpWidget(
      _buildApp(novels: [novel], scraper: _FakeScraper(), store: store),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 chapters saved offline'), findsOneWidget);
    expect(find.text('#7 · The duel'), findsOneWidget);
    expect(find.text('The duel'), findsNothing);
  });
}
