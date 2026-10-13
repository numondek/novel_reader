import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/app/router/app_router.dart';
import 'package:novel_reader/core/network/dio_client.dart';
import 'package:novel_reader/core/widgets/add_link_sheet.dart';
import 'package:novel_reader/core/widgets/links_sheet.dart';
import 'package:novel_reader/features/novels/domain/models/read_novel.dart';
import 'package:novel_reader/features/novels/presentation/pages/novel_import_page.dart';
import 'package:novel_reader/features/novels/presentation/pages/novels_page.dart';
import 'package:novel_reader/features/novels/presentation/providers/read_novels_provider.dart';
import 'package:novel_reader/features/prefetch/presentation/providers/offline_chapter_store_provider.dart';
import 'package:novel_reader/features/prefetch/presentation/widgets/offline_chapters_sheet.dart';
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
  Future<void> remove(String novelKey) async {
    saved.remove(novelKey);
  }

  @override
  Future<ExtractedChapter?> find(String url) async => null;
}

/// Fails every import, which is enough to watch the link travel from
/// the sheet into the import page without opening a reader.
class _ThrowingScraper extends ScraperRepository {
  _ThrowingScraper()
    : super(dioClient: DioClient(), adapter: GenericNovelAdapter());

  @override
  Future<ExtractedChapter> extractChapter(String url) async {
    throw Exception('No chapter at $url');
  }
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

Widget buildPage(
  List<ReadNovel> seed, {
  OfflineChapterStore? store,
  List<ManhwaSeries> shelf = const [],
}) {
  return ProviderScope(
    overrides: [
      readNovelsProvider.overrideWith(() => _SeededReadNovels(seed)),
      manhwaSeriesProvider.overrideWith(() => _SeededShelf(shelf)),
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

    // Nothing here knows how long the chapter was, so no share yet.
    expect(find.textContaining('% read'), findsNothing);
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
    expect(find.text('Add a link'), findsOneWidget);
  });

  testWidgets('the app bar plus opens the link sheet', (tester) async {
    await tester.pumpWidget(buildPage(seedEntries()));
    await tester.pump();

    await tester.tap(find.byTooltip('Add link'));
    await tester.pumpAndSettle();

    expect(find.byType(AddLinkSheet), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byType(AddLinkSheet), findsNothing);
    expect(find.text('Nova'), findsOneWidget);
  });

  testWidgets('the empty list offers a link to add', (tester) async {
    await tester.pumpWidget(buildPage(const []));
    await tester.pump();

    await tester.tap(find.text('Add a link'));
    await tester.pumpAndSettle();

    expect(find.byType(AddLinkSheet), findsOneWidget);
  });

  testWidgets('adding a link opens the import flow', (tester) async {
    final router = AppRouter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readNovelsProvider.overrideWith(() => _SeededReadNovels(const [])),
          manhwaSeriesProvider.overrideWith(() => _SeededShelf(const [])),
          scraperRepositoryProvider.overrideWithValue(_ThrowingScraper()),
        ],
        child: MaterialApp.router(routerConfig: router.config()),
      ),
    );
    await tester.pumpAndSettle();

    router.push(const NovelsRoute());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add link'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'example.com/book/1');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.byType(NovelImportPage), findsOneWidget);
    expect(find.text('Unable to extract chapter'), findsOneWidget);

    // Let the failure snack bar play out before the test ends.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('delete also drops the novel\'s offline chapters', (
    tester,
  ) async {
    final store = _FakeStore({
      'novel:site.com:Nova': [
        savedChapter('https://site.com/nova/1', 'Chapter 1 - Beginning'),
      ],
      'novel:other.org:Sol': [
        savedChapter('https://other.org/sol/1', 'Chapter 1 - Solo'),
      ],
    });

    await tester.pumpWidget(buildPage(seedEntries(), store: store));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('1 offline'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pump();
    await tester.pump();

    expect(find.text('Nova'), findsNothing);
    expect(store.saved.containsKey('novel:site.com:Nova'), isFalse);

    // What another novel saved stays on the device.
    expect(store.saved.keys, ['novel:other.org:Sol']);
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

  testWidgets('the order button reverses the list', (tester) async {
    await tester.pumpWidget(buildPage(seedEntries()));
    await tester.pump();

    // Read history is stored newest-first, so the button offers the
    // ascending order.
    expect(find.byTooltip('Sort ascending'), findsOneWidget);

    final nova = tester.getTopLeft(find.text('Nova')).dy;
    final last =
        tester.getTopLeft(find.text('Obtaining the Ancient Holy Body')).dy;
    expect(nova, lessThan(last));

    await tester.tap(find.byTooltip('Sort ascending'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Sort descending'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Obtaining the Ancient Holy Body')).dy,
      lessThan(tester.getTopLeft(find.text('Nova')).dy),
    );
  });

  testWidgets('the offline chapter list can be reversed', (tester) async {
    final store = _FakeStore({
      'novel:site.com:Nova': [
        savedChapter('https://site.com/nova/1', 'Chapter 1 - Beginning'),
        savedChapter('https://site.com/nova/2', 'Chapter 2 - The duel'),
      ],
    });

    await tester.pumpWidget(buildPage(seedEntries(), store: store));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Offline chapters'));
    await tester.pumpAndSettle();

    Finder sheetToggle(String tooltip) => find.descendant(
      of: find.byType(OfflineChaptersSheet),
      matching: find.byTooltip(tooltip),
    );

    // Saved chapters start in reading order.
    expect(sheetToggle('Sort descending'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Chapter 1 - Beginning')).dy,
      lessThan(tester.getTopLeft(find.text('Chapter 2 - The duel')).dy),
    );

    await tester.tap(sheetToggle('Sort descending'));
    await tester.pumpAndSettle();

    expect(sheetToggle('Sort ascending'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Chapter 2 - The duel')).dy,
      lessThan(tester.getTopLeft(find.text('Chapter 1 - Beginning')).dy),
    );
  });

  testWidgets('series on the shelf stay on the manhwa page', (tester) async {
    final history = [
      ...seedEntries(),
      ReadNovel(
        key: 'manhwa:site.com/manga/grid-nova',
        url: 'https://site.com/manga/grid-nova/chapter-1',
        novelTitle: 'Grid Nova',
        chapterTitle: 'Chapter 1',
        readAt: DateTime.now(),
      ),
      ReadNovel(
        key: 'url:site.com:manga',
        url: 'https://site.com/manga/grid-sol/chapter-1',
        chapterTitle: 'Chapter 1 - Panel',
        readAt: DateTime.now(),
      ),
    ];

    final shelf = [
      ManhwaSeries(
        novelKey: 'manhwa:site.com/manga/grid-nova',
        title: 'Grid Nova',
        sourceUrl: 'https://site.com/manga/grid-nova',
        openedAt: DateTime.now(),
      ),
      ManhwaSeries(
        novelKey: 'manhwa:site.com/manga/grid-sol',
        title: 'Grid Sol',
        sourceUrl: 'https://site.com/manga/grid-sol',
        openedAt: DateTime.now(),
      ),
    ];

    await tester.pumpWidget(buildPage(history, shelf: shelf));
    await tester.pumpAndSettle();

    expect(find.text('Nova'), findsOneWidget);
    expect(find.text('Sol'), findsOneWidget);

    // Picture series belong to the shelf, not to this list.
    expect(find.text('Grid Nova'), findsNothing);
    expect(find.text('Grid Sol'), findsNothing);
    expect(find.text('Chapter 1 - Panel'), findsNothing);
  });

  testWidgets('a chapter read partway says how far', (tester) async {
    await tester.pumpWidget(
      buildPage([
        ReadNovel(
          key: 'novel:site.com:Nova',
          url: 'https://site.com/nova/chapter-2',
          novelTitle: 'Nova',
          chapterTitle: 'Chapter 2 - The duel',
          paragraphIndex: 4,
          paragraphCount: 11,
          chapterProgress: const {
            'https://site.com/nova/chapter-1': [8, 8],
            'https://site.com/nova/chapter-2': [4, 11],
          },
          readAt: DateTime.now(),
        ),
        ReadNovel(
          key: 'novel:other.org:Sol',
          url: 'https://other.org/sol/chapter-9',
          novelTitle: 'Sol',
          chapterTitle: 'Nightfall',
          readAt: DateTime.now(),
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('Nova'), findsOneWidget);
    expect(find.textContaining('40% read'), findsOneWidget);

    // A chapter title without a number takes it from the link.
    expect(find.textContaining('#9 · Nightfall'), findsOneWidget);
  });

  testWidgets('the link icon keeps another link on the novel', (tester) async {
    await tester.pumpWidget(buildPage(seedEntries()));
    await tester.pump();

    await tester.tap(find.byTooltip('Links').first);
    await tester.pumpAndSettle();

    expect(find.byType(LinksSheet), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'site.com/nova/alt');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.byType(LinksSheet), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(NovelsPage)),
    );
    final entries = await container.read(readNovelsProvider.future);
    final nova = entries.firstWhere(
      (entry) => entry.key == 'novel:site.com:Nova',
    );

    expect(nova.links, ['https://site.com/nova/alt']);
    expect(
      entries.where((entry) => entry.key == 'novel:other.org:Sol').single.links,
      isEmpty,
    );
  });

  testWidgets('a saved link opens the import flow', (tester) async {
    final router = AppRouter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readNovelsProvider.overrideWith(
            () => _SeededReadNovels([
              ReadNovel(
                key: 'novel:site.com:Nova',
                url: 'https://site.com/nova/chapter-2',
                novelTitle: 'Nova',
                chapterTitle: 'Chapter 2 - The duel',
                links: const ['https://site.com/nova/alt'],
                readAt: DateTime.now(),
              ),
            ]),
          ),
          manhwaSeriesProvider.overrideWith(() => _SeededShelf(const [])),
          scraperRepositoryProvider.overrideWithValue(_ThrowingScraper()),
        ],
        child: MaterialApp.router(routerConfig: router.config()),
      ),
    );
    await tester.pumpAndSettle();

    router.push(const NovelsRoute());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Links').first);
    await tester.pumpAndSettle();

    expect(find.byType(LinksSheet), findsOneWidget);
    expect(find.text('https://site.com/nova/alt'), findsOneWidget);

    await tester.tap(find.text('https://site.com/nova/alt'));
    await tester.pumpAndSettle();

    expect(find.byType(LinksSheet), findsNothing);
    expect(find.byType(NovelImportPage), findsOneWidget);
    expect(find.text('Unable to extract chapter'), findsOneWidget);

    // Let the failure snack bar play out before the test ends.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
