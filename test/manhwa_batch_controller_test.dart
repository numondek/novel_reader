import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/network/dio_client.dart';
import 'package:novel_reader/features/scraper/data/repositories/scraper_repository.dart';
import 'package:novel_reader/features/scraper/data/services/generic_novel_adapter.dart';
import 'package:novel_reader/features/scraper/domain/models/extracted_chapter.dart';
import 'package:novel_reader/features/scraper/domain/services/offline_chapter_store.dart';
import 'package:novel_reader/features/scraper/presentation/providers/manhwa_batch_provider.dart';

const String seriesUrl = 'https://example.com/manga/demo';
const String novelKey = 'manhwa:example.com/manga/demo';

/// A contents page that lists its chapters newest first, the way
/// they are usually published.
String _toc({int count = 12}) {
  final buffer = StringBuffer('<html><body>');

  for (var number = count; number >= 1; number--) {
    buffer.write('<a href="/manga/demo/chapter-$number">Chapter $number</a>');
  }

  return '${buffer.toString()}</body></html>';
}

ExtractedChapter _chapter(int number) {
  return ExtractedChapter(
    title: 'Chapter $number',
    paragraphs: const [],
    url: '$seriesUrl/chapter-$number',
    imageUrls: ['https://cdn.example.com/$number.jpg'],
  );
}

class _FakeScraper extends ScraperRepository {
  _FakeScraper()
    : super(dioClient: DioClient(), adapter: GenericNovelAdapter());

  String? html;
  final Map<String, ExtractedChapter> chapters = <String, ExtractedChapter>{};
  final List<String> requests = <String>[];

  @override
  Future<String> loadHtml(String url) async {
    final page = html;
    if (page == null) {
      throw Exception('Network is down');
    }
    return page;
  }

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

_FakeScraper _scraper({int count = 12}) {
  final scraper = _FakeScraper()..html = _toc(count: count);

  for (var number = 1; number <= count; number++) {
    scraper.chapters['$seriesUrl/chapter-$number'] = _chapter(number);
  }

  return scraper;
}

ManhwaBatchController _controller({
  required _FakeScraper scraper,
  required _FakeStore store,
}) {
  return ManhwaBatchController(
    target: const ManhwaBatchTarget(novelKey: novelKey, sourceUrl: seriesUrl),
    scraper: scraper,
    store: store,
  );
}

void main() {
  test('the first batch saves the ten earliest chapters', () async {
    final scraper = _scraper();
    final store = _FakeStore();
    final controller = _controller(scraper: scraper, store: store);

    await controller.saveNextBatch();

    expect(scraper.requests, hasLength(10));
    expect(scraper.requests.first, '$seriesUrl/chapter-1');
    expect(scraper.requests.last, '$seriesUrl/chapter-10');
    expect(store.novels[novelKey], hasLength(10));

    final saved = [for (final chapter in store.novels[novelKey]!) chapter.url];
    expect(saved.first, '$seriesUrl/chapter-1');
    expect(saved.last, '$seriesUrl/chapter-10');

    expect(controller.state.savedCount, 10);
    expect(controller.state.totalCount, 10);
    expect(controller.state.isSaving, isFalse);
    expect(controller.state.error, isNull);
  });

  test('the next batch continues after the last saved chapter', () async {
    final scraper = _scraper();
    final store =
        _FakeStore()
          ..novels[novelKey] = [
            for (var number = 1; number <= 10; number++) _chapter(number),
          ];
    final controller = _controller(scraper: scraper, store: store);

    await controller.saveNextBatch();

    expect(scraper.requests, [
      '$seriesUrl/chapter-11',
      '$seriesUrl/chapter-12',
    ]);
    expect(store.novels[novelKey], hasLength(12));
    expect(controller.state.savedCount, 2);
    expect(controller.state.totalCount, 2);
  });

  test('a series with nothing left says so', () async {
    final scraper = _scraper();
    final store =
        _FakeStore()
          ..novels[novelKey] = [
            for (var number = 1; number <= 12; number++) _chapter(number),
          ];
    final controller = _controller(scraper: scraper, store: store);

    await controller.saveNextBatch();

    expect(scraper.requests, isEmpty);
    expect(controller.state.isSaving, isFalse);
    expect(controller.state.error, 'Every chapter is saved.');
  });

  test('a failing table of contents is reported', () async {
    final scraper = _FakeScraper();
    final store = _FakeStore();
    final controller = _controller(scraper: scraper, store: store);

    await controller.saveNextBatch();

    expect(controller.state.isSaving, isFalse);
    expect(controller.state.error, 'Network is down');
  });
}
