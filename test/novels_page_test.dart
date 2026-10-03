import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/novels/domain/models/read_novel.dart';
import 'package:novel_reader/features/novels/presentation/pages/novels_page.dart';
import 'package:novel_reader/features/novels/presentation/providers/read_novels_provider.dart';
import 'package:novel_reader/features/prefetch/presentation/providers/offline_chapter_store_provider.dart';
import 'package:novel_reader/features/scraper/domain/models/extracted_chapter.dart';
import 'package:novel_reader/features/scraper/domain/services/offline_chapter_store.dart';

class _SeededReadNovels extends ReadNovelsController {
  _SeededReadNovels(this.seed);

  final List<ReadNovel> seed;

  @override
  Future<List<ReadNovel>> build() async => seed;
}

class _FakeStore implements OfflineChapterStore {
  _FakeStore(this.saved);

  final Map<String, List<ExtractedChapter>> saved;

  @override
  Future<List<ExtractedChapter>> load(String novelKey) async =>
      saved[novelKey] ?? const [];

  @override
  Future<int> count(String novelKey) async =>
      (saved[novelKey] ?? const []).length;

  @override
  Future<void> save(String novelKey, ExtractedChapter chapter) async {}

  @override
  Future<ExtractedChapter?> find(String url) async => null;
}

List<ReadNovel> seedEntries() {
  return [
    ReadNovel(
      key: 'novel:site.com:Nova',
      url: 'https://site.com/nova/chapter-2',
      novelTitle: 'Nova',
      chapterTitle: 'Chapter 2 - The duel',
      readAt: DateTime.now(),
    ),
    ReadNovel(
      key: 'novel:other.org:Sol',
      url: 'https://other.org/sol/chapter-9',
      novelTitle: 'Sol',
      chapterTitle: 'Chapter 9 - Nightfall',
      readAt: DateTime.now(),
    ),
    ReadNovel(
      key: 'url:site2.com:bare',
      url: 'https://site2.com/bare/chapter-5',
      chapterTitle: 'Chapter 5 - Lost',
      readAt: DateTime.now(),
    ),
    ReadNovel(
      key: 'novel:czbooks.net:開局簽到荒古聖體',
      url: 'https://czbooks.net/n/s6pcm6/ucp0ldl2',
      novelTitle: '開局簽到荒古聖體',
      novelTitleEn: 'Obtaining the Ancient Holy Body',
      chapterTitle: '第4682章 十小聖之首',
      chapterTitleEn: 'Chapter 4682 - Head of the Ten Saints',
      readAt: DateTime.now(),
    ),
  ];
}

ExtractedChapter savedChapter(String url, String title) {
  return ExtractedChapter(
    title: title,
    paragraphs: const ['Cached text.'],
    url: url,
  );
}

Widget buildPage(List<ReadNovel> seed, {OfflineChapterStore? store}) {
  return ProviderScope(
    overrides: [
      readNovelsProvider.overrideWith(() => _SeededReadNovels(seed)),
      if (store != null) offlineChapterStoreProvider.overrideWithValue(store),
    ],
    child: const MaterialApp(home: NovelsPage()),
  );
}

void main() {
  testWidgets('shows novels by name with chapter context', (tester) async {
    await tester.pumpWidget(buildPage(seedEntries()));
    await tester.pump();

    expect(find.text('Nova'), findsOneWidget);
    expect(find.text('Sol'), findsOneWidget);
    expect(find.textContaining('Chapter 2 - The duel'), findsOneWidget);
    expect(find.textContaining('site.com'), findsOneWidget);
    expect(find.textContaining('other.org'), findsOneWidget);

    expect(find.text('Chapter 5 - Lost'), findsOneWidget);
    expect(find.textContaining('site2.com'), findsOneWidget);

    expect(find.text('Obtaining the Ancient Holy Body'), findsOneWidget);
    expect(
      find.textContaining('Chapter 4682 - Head of the Ten Saints'),
      findsOneWidget,
    );
    expect(find.text('開局簽到荒古聖體'), findsNothing);
    expect(find.textContaining('第4682章'), findsNothing);
  });

  testWidgets('delete removes only the tapped entry', (tester) async {
    await tester.pumpWidget(buildPage(seedEntries()));
    await tester.pump();

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pump();
    await tester.pump();

    expect(find.text('Nova'), findsNothing);
    expect(find.text('Sol'), findsOneWidget);
    expect(find.text('Chapter 5 - Lost'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(NovelsPage)),
    );
    final remaining = await container.read(readNovelsProvider.future);
    expect(remaining, hasLength(3));
    expect(
      remaining.map((entry) => entry.key),
      containsAll([
        'novel:other.org:Sol',
        'url:site2.com:bare',
        'novel:czbooks.net:開局簽到荒古聖體',
      ]),
    );
  });

  testWidgets('shows an empty state with no entries', (tester) async {
    await tester.pumpWidget(buildPage(const []));
    await tester.pump();

    expect(find.text('No read novels yet'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsNothing);
  });

  testWidgets('a novel with saved chapters shows its offline list', (
    tester,
  ) async {
    final store = _FakeStore({
      'novel:site.com:Nova': [
        savedChapter('https://site.com/nova/1', 'Chapter 1 - Beginning'),
        savedChapter('https://site.com/nova/2', 'Chapter 2 - The duel'),
      ],
    });

    await tester.pumpWidget(buildPage(seedEntries(), store: store));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('2 offline'), findsOneWidget);
    expect(find.byTooltip('Offline chapters'), findsOneWidget);

    await tester.tap(find.byTooltip('Offline chapters'));
    await tester.pumpAndSettle();

    expect(find.text('Chapter 1 - Beginning'), findsOneWidget);
    expect(find.text('Chapter 2 - The duel'), findsOneWidget);
    expect(find.text('Chapter 9 - Nightfall'), findsNothing);
  });

  testWidgets('a novel without saved chapters has no offline button', (
    tester,
  ) async {
    final store = _FakeStore({
      'novel:site.com:Nova': [
        savedChapter('https://site.com/nova/1', 'Chapter 1 - Beginning'),
      ],
    });

    await tester.pumpWidget(buildPage(seedEntries(), store: store));
    await tester.pump();
    await tester.pump();

    // Only Nova saved anything; the other entries stay clean.
    expect(find.byTooltip('Offline chapters'), findsOneWidget);
    expect(find.textContaining('1 offline'), findsOneWidget);
    expect(find.textContaining('0 offline'), findsNothing);
  });
}
