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
import 'package:novel_reader/features/scraper/domain/services/offline_chapter_store.dart';
import 'package:novel_reader/features/scraper/presentation/providers/scraper_providers.dart';

class _SeededReadNovels extends ReadNovelsController {
  _SeededReadNovels(this.seed);

  final List<ReadNovel> seed;

  @override
  Future<List<ReadNovel>> build() async => seed;
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
  Future<ExtractedChapter?> find(String url) async => urls[url];
}

final ReadNovel novel = ReadNovel(
  key: 'novel:example.com:Demo',
  url: 'https://example.com/1',
  novelTitle: 'Demo',
  chapterTitle: 'Chapter 1',
  readAt: DateTime(2026),
);

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
}) {
  return ProviderScope(
    overrides: [
      readNovelsProvider.overrideWith(() => _SeededReadNovels(novels)),
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
}
