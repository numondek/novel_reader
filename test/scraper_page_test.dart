import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/app/router/app_router.dart';
import 'package:novel_reader/core/network/dio_client.dart';
import 'package:novel_reader/core/widgets/empty_state.dart';
import 'package:novel_reader/features/novels/domain/models/read_novel.dart';
import 'package:novel_reader/features/novels/presentation/providers/read_novels_provider.dart';
import 'package:novel_reader/features/prefetch/presentation/providers/offline_chapter_store_provider.dart';
import 'package:novel_reader/features/reader/presentation/pages/reader_page.dart';
import 'package:novel_reader/features/scraper/data/repositories/scraper_repository.dart';
import 'package:novel_reader/features/scraper/data/services/generic_novel_adapter.dart';
import 'package:novel_reader/features/scraper/domain/models/extracted_chapter.dart';
import 'package:novel_reader/features/scraper/domain/services/offline_chapter_store.dart';
import 'package:novel_reader/features/scraper/presentation/pages/scraper_page.dart';
import 'package:novel_reader/features/scraper/presentation/providers/scraper_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

const String seriesUrl = 'https://example.com/manhwa/demo';

const String seriesHtml = '''
<html><body>
  <a href="/manhwa/demo/chapter-1">Chapter 1</a>
  <a href="/manhwa/demo/chapter-2">Chapter 2</a>
  <a href="/genres/action">Action</a>
</body></html>
''';

const String shelfUrl = 'https://example.com/manga/grid-demo';

/// A series long enough to need more than one batch, listed newest
/// first the way contents pages usually do.
String shelfHtml() {
  final buffer = StringBuffer(
    '<html><head><title>Grid Demo</title></head><body>',
  );

  for (var number = 12; number >= 1; number--) {
    buffer.write(
      '<a href="/manga/grid-demo/chapter-$number">Chapter $number</a>',
    );
  }

  return '${buffer.toString()}</body></html>';
}

const String chapterUrl =
    'https://asurascans.com/comics/myst-might-mayhem-bd5bdaf8/chapter/116';

const String chapterPageUrl =
    'https://asurascans.com/comics/myst-might-mayhem-bd5bdaf8';

/// A chapter page the way asurascans serves one: neighbours as
/// `<link>` tags, a breadcrumb home, and not a single chapter link.
String chapterPageHtml() => '''
<html><head>
  <link rel="prev" href="/comics/myst-might-mayhem-bd5bdaf8/chapter/115">
  <link rel="next" href="/comics/myst-might-mayhem-bd5bdaf8/chapter/117">
</head><body>
  <a href="/comics/myst-might-mayhem-bd5bdaf8">Myst, Might, Mayhem</a>
  <h1>Chapter 116</h1>
</body></html>
''';

/// The series behind that chapter, cards stacking label, subtitle
/// and date the way asurascans renders them.
String seriesPageHtml() {
  final buffer = StringBuffer(
    '<html><head><title>Myst, Might, Mayhem</title></head><body>',
  );

  for (var number = 116; number >= 105; number--) {
    buffer.write(
      '<a href="/comics/myst-might-mayhem-bd5bdaf8/chapter/$number">'
      '<div><div><span>Chapter $number</span></div>'
      '<div>Jo Taechung</div><div>2 weeks ago</div></div></a>',
    );
  }

  return '${buffer.toString()}</body></html>';
}

ExtractedChapter _chapter(int number) {
  return ExtractedChapter(
    title: 'Chapter $number',
    paragraphs: const [],
    url: '$seriesUrl/chapter-$number',
    imageUrls: ['https://cdn.example.com/$number.jpg'],
    nextChapterUrl: number < 2 ? '$seriesUrl/chapter-${number + 1}' : null,
  );
}

ExtractedChapter _shelfChapter(int number) {
  return ExtractedChapter(
    title: 'Chapter $number',
    paragraphs: const [],
    url: '$shelfUrl/chapter-$number',
    imageUrls: ['https://cdn.example.com/$number.jpg'],
  );
}

class _FakeScraper extends ScraperRepository {
  _FakeScraper()
    : super(dioClient: DioClient(), adapter: GenericNovelAdapter());

  String? html;
  final Map<String, String> pages = <String, String>{};
  final Map<String, ExtractedChapter> chapters = <String, ExtractedChapter>{};
  final List<String> extracted = <String>[];

  @override
  Future<String> loadHtml(String url) async {
    final page = pages[url] ?? html;
    if (page == null) {
      throw Exception('Network is down');
    }
    return page;
  }

  @override
  Future<ExtractedChapter> extractChapter(String url) async {
    extracted.add(url);

    final chapter = chapters[url];
    if (chapter == null) {
      throw Exception('No chapter for $url');
    }

    return chapter;
  }
}

class _SeededReadNovels extends ReadNovelsController {
  _SeededReadNovels(this.seed);

  final List<ReadNovel> seed;

  @override
  Future<List<ReadNovel>> build() async => seed;
}

class _FakeStore implements OfflineChapterStore {
  final Map<String, List<ExtractedChapter>> novels =
      <String, List<ExtractedChapter>>{};

  @override
  Future<List<ExtractedChapter>> load(String novelKey) async {
    return List<ExtractedChapter>.of(novels[novelKey] ?? const []);
  }

  @override
  Future<int> count(String novelKey) async => novels[novelKey]?.length ?? 0;

  @override
  Future<void> save(String novelKey, ExtractedChapter chapter) async {
    (novels[novelKey] ??= <ExtractedChapter>[]).add(chapter);
  }

  @override
  Future<void> remove(String novelKey) async {
    novels.remove(novelKey);
  }

  @override
  Future<ExtractedChapter?> find(String url) async {
    for (final chapters in novels.values) {
      for (final chapter in chapters) {
        if (chapter.url == url) return chapter;
      }
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeScraper scraper;
  late _FakeStore store;
  late AppRouter router;
  late Directory tempDir;

  setUp(() {
    scraper = _FakeScraper();
    store = _FakeStore();
    router = AppRouter();

    // The shelf keeps its cards in the same file store the app uses,
    // so its provider must not wait on platform channels here.
    SharedPreferences.setMockInitialValues({});

    tempDir = Directory.systemTemp.createTempSync('novel_reader_scraper');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tempDir.path;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    tempDir.deleteSync(recursive: true);
  });

  Widget buildApp({List<ReadNovel> history = const []}) {
    return ProviderScope(
      overrides: [
        scraperRepositoryProvider.overrideWithValue(scraper),
        offlineChapterStoreProvider.overrideWithValue(store),
        readNovelsProvider.overrideWith(() => _SeededReadNovels(history)),
      ],
      child: MaterialApp.router(routerConfig: router.config()),
    );
  }

  Future<void> openScraper(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    router.push(const ScraperRoute());
    await tester.pumpAndSettle();

    expect(find.byType(ScraperPage), findsOneWidget);
  }

  Future<void> openUrl(WidgetTester tester, String url) async {
    final page = find.byType(ScraperPage);

    await tester.enterText(
      find.descendant(of: page, matching: find.byType(TextField)),
      url,
    );
    await tester.tap(find.descendant(of: page, matching: find.text('Open')));
    await tester.pumpAndSettle();
  }

  testWidgets('opening a series lists its chapters', (tester) async {
    scraper.html = seriesHtml;

    await tester.pumpWidget(buildApp());
    await openScraper(tester);

    expect(find.text('Read manhwa offline'), findsOneWidget);

    await openUrl(tester, seriesUrl);

    expect(find.text('2 chapters · 0 saved'), findsOneWidget);
    expect(find.text('Chapter 1'), findsOneWidget);
    expect(find.text('Chapter 2'), findsOneWidget);
    expect(find.text('Action'), findsNothing);
  });

  testWidgets('saving a chapter downloads it and marks it saved', (
    tester,
  ) async {
    scraper.html = seriesHtml;
    scraper.chapters['$seriesUrl/chapter-1'] = _chapter(1);

    await tester.pumpWidget(buildApp());
    await openScraper(tester);
    await openUrl(tester, seriesUrl);

    await tester.tap(find.byTooltip('Save offline').first);
    await tester.pumpAndSettle();

    expect(scraper.extracted, ['$seriesUrl/chapter-1']);
    expect(store.novels.values, hasLength(1));
    expect(store.novels.values.single.single.url, '$seriesUrl/chapter-1');

    expect(find.text('2 chapters · 1 saved'), findsOneWidget);
    expect(find.text('Saved offline'), findsOneWidget);
  });

  testWidgets('save all downloads every missing chapter', (tester) async {
    scraper.html = seriesHtml;
    scraper.chapters['$seriesUrl/chapter-1'] = _chapter(1);
    scraper.chapters['$seriesUrl/chapter-2'] = _chapter(2);

    await tester.pumpWidget(buildApp());
    await openScraper(tester);
    await openUrl(tester, seriesUrl);

    await tester.tap(find.text('Save all'));
    await tester.pumpAndSettle();

    expect(scraper.extracted, hasLength(2));
    expect(find.text('2 chapters · 2 saved'), findsOneWidget);
    expect(find.text('Saved offline'), findsNWidgets(2));

    final saveAll = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Save all'),
    );
    expect(saveAll.onPressed, isNull);
  });

  testWidgets('a page without chapters reports the problem', (tester) async {
    scraper.html = '<html><body><p>No chapters here.</p></body></html>';

    await tester.pumpWidget(buildApp());
    await openScraper(tester);
    await openUrl(tester, seriesUrl);

    expect(
      find.descendant(
        of: find.byType(EmptyState),
        matching: find.text('Could not open the page'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(EmptyState),
        matching: find.textContaining('No chapters found'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('opening a saved chapter reaches the reader', (tester) async {
    scraper.html = seriesHtml;
    scraper.chapters['$seriesUrl/chapter-1'] = _chapter(1);

    await tester.pumpWidget(buildApp());
    await openScraper(tester);
    await openUrl(tester, seriesUrl);

    await tester.tap(find.text('Chapter 1'));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderPage), findsOneWidget);
    expect(find.text('Chapter 1'), findsWidgets);
  });

  testWidgets('an opened manhwa is kept on the shelf as a cover', (
    tester,
  ) async {
    scraper.html = shelfHtml();

    await tester.pumpWidget(buildApp());
    await openScraper(tester);
    await openUrl(tester, shelfUrl);

    expect(find.text('12 chapters · 0 saved'), findsOneWidget);

    await tester.tap(find.byTooltip('My manhwa'));
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Grid Demo'), findsOneWidget);
    expect(find.text('Nothing saved yet'), findsOneWidget);
    expect(find.text('Read manhwa offline'), findsNothing);

    // Nothing has been read yet, so the card offers no resume.
    expect(find.byTooltip('Resume reading'), findsNothing);
  });

  testWidgets('a shelf card lists its offline chapters and saves the next '
      'ten', (tester) async {
    scraper.html = shelfHtml();

    for (var number = 1; number <= 12; number++) {
      scraper.chapters['$shelfUrl/chapter-$number'] = _shelfChapter(number);
    }

    await tester.pumpWidget(buildApp());
    await openScraper(tester);
    await openUrl(tester, shelfUrl);
    await tester.tap(find.byTooltip('My manhwa'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Grid Demo'));
    await tester.pumpAndSettle();

    expect(find.text('No chapters saved for this manhwa yet.'), findsOneWidget);

    // FilledButton.icon builds a private subclass, so match the label.
    final saveNext = find.text('Save next 10 chapters');
    expect(saveNext, findsOneWidget);

    await tester.tap(saveNext);
    await tester.pumpAndSettle();

    expect(scraper.extracted, hasLength(10));
    expect(scraper.extracted.first, '$shelfUrl/chapter-1');
    expect(scraper.extracted.last, '$shelfUrl/chapter-10');

    expect(store.novels.values.single, hasLength(10));
    expect(find.text('Saved 10 of 10'), findsOneWidget);
    expect(find.text('Chapter 1'), findsOneWidget);
    expect(find.text('No chapters saved for this manhwa yet.'), findsNothing);
  });

  testWidgets('chapters read before are marked in the list', (tester) async {
    scraper.html = seriesHtml;

    await tester.pumpWidget(
      buildApp(
        history: [
          ReadNovel(
            key: 'manhwa:example.com/manhwa/demo',
            url: '$seriesUrl/chapter-1',
            chapterTitle: 'Chapter 1',
            chapterProgress: const {
              'https://example.com/manhwa/demo/chapter-1': [1, 3],
            },
            readAt: DateTime.now(),
          ),
        ],
      ),
    );
    await openScraper(tester);
    await openUrl(tester, seriesUrl);

    expect(find.text('2 chapters · 0 saved'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    expect(find.text('50% read'), findsOneWidget);
  });

  testWidgets('a shelf card resumes where the reader left off', (tester) async {
    scraper.html = shelfHtml();

    for (var number = 1; number <= 12; number++) {
      scraper.chapters['$shelfUrl/chapter-$number'] = _shelfChapter(number);
    }

    await tester.pumpWidget(
      buildApp(
        history: [
          ReadNovel(
            key: 'manhwa:example.com/manga/grid-demo',
            url: '$shelfUrl/chapter-7',
            chapterTitle: 'Chapter 7',
            chapterProgress: const {
              'https://example.com/manga/grid-demo/chapter-7': [4, 9],
            },
            readAt: DateTime.now(),
          ),
        ],
      ),
    );
    await openScraper(tester);
    await openUrl(tester, shelfUrl);
    await tester.tap(find.byTooltip('My manhwa'));
    await tester.pumpAndSettle();

    expect(find.text('Grid Demo'), findsOneWidget);
    expect(find.text('Nothing saved yet'), findsOneWidget);
    expect(find.text('50% read'), findsOneWidget);

    final resume = find.byTooltip('Resume reading');
    expect(resume, findsOneWidget);

    await tester.tap(resume);
    await tester.pumpAndSettle();

    expect(scraper.extracted, ['$shelfUrl/chapter-7']);
    expect(find.byType(ReaderPage), findsOneWidget);
    expect(find.text('Chapter 7'), findsWidgets);
  });

  testWidgets('a chapter title without a number still shows it', (
    tester,
  ) async {
    scraper.html = '''
<html><body>
  <a href="/manhwa/demo/chapter-1">The beginning</a>
  <a href="/manhwa/demo/chapter-2">The duel</a>
</body></html>
''';

    await tester.pumpWidget(buildApp());
    await openScraper(tester);
    await openUrl(tester, seriesUrl);

    expect(find.text('#1 · The beginning'), findsOneWidget);
    expect(find.text('#2 · The duel'), findsOneWidget);
    expect(find.text('The duel'), findsNothing);
  });

  testWidgets('a chapter page that lists nothing opens its series', (
    tester,
  ) async {
    scraper.pages[chapterUrl] = chapterPageHtml();
    scraper.pages[chapterPageUrl] = seriesPageHtml();

    await tester.pumpWidget(buildApp());
    await openScraper(tester);
    await openUrl(tester, chapterUrl);

    expect(find.text('12 chapters · 0 saved'), findsOneWidget);
    expect(find.text('Chapter 105'), findsOneWidget);

    // The series, not the chapter, is what went on the shelf.
    await tester.tap(find.byTooltip('My manhwa'));
    await tester.pumpAndSettle();

    expect(find.text('Myst, Might, Mayhem'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
  });

  testWidgets('deleting a manhwa clears its shelf, progress and chapters', (
    tester,
  ) async {
    scraper.html = shelfHtml();

    // Two chapters downloaded for the card's manhwa.
    store.novels['manhwa:example.com/manga/grid-demo'] = [
      _shelfChapter(1),
      _shelfChapter(2),
    ];

    await tester.pumpWidget(
      buildApp(
        history: [
          ReadNovel(
            key: 'manhwa:example.com/manga/grid-demo',
            url: '$shelfUrl/chapter-7',
            chapterTitle: 'Chapter 7',
            chapterProgress: const {
              'https://example.com/manga/grid-demo/chapter-7': [4, 9],
            },
            readAt: DateTime.now(),
          ),
        ],
      ),
    );
    await openScraper(tester);
    await openUrl(tester, shelfUrl);
    await tester.tap(find.byTooltip('My manhwa'));
    await tester.pumpAndSettle();

    expect(find.text('Grid Demo'), findsOneWidget);
    expect(find.text('2 saved'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ScraperPage)),
      listen: false,
    );

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Grid Demo'), findsNothing);
    expect(find.byType(GridView), findsNothing);
    expect(find.text('Read manhwa offline'), findsOneWidget);

    // The offline chapters go with the card.
    expect(store.novels, isEmpty);

    final history = await container.read(readNovelsProvider.future);
    expect(history, isEmpty);
  });
}
