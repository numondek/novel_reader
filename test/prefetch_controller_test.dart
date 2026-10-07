import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/network/dio_client.dart';
import 'package:novel_reader/features/novels/domain/models/read_novel.dart';
import 'package:novel_reader/features/prefetch/presentation/providers/prefetch_controller_provider.dart';
import 'package:novel_reader/features/scraper/data/repositories/scraper_repository.dart';
import 'package:novel_reader/features/scraper/data/services/generic_novel_adapter.dart';
import 'package:novel_reader/features/scraper/domain/models/extracted_chapter.dart';
import 'package:novel_reader/features/scraper/domain/services/offline_chapter_store.dart';

class _FakeScraper extends ScraperRepository {
  _FakeScraper()
    : super(dioClient: DioClient(), adapter: GenericNovelAdapter());

  final Map<String, ExtractedChapter> chapters = <String, ExtractedChapter>{};
  final List<String> requests = <String>[];
  int? failOnRequest;

  @override
  Future<ExtractedChapter> extractChapter(String url) async {
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
  bool failSave = false;

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
    if (failSave) throw Exception('Disk full');

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

ExtractedChapter chapter(int number, {int last = 50}) {
  return ExtractedChapter(
    title: 'Chapter $number',
    paragraphs: <String>['Text $number'],
    url: 'https://example.com/$number',
    nextChapterUrl: number < last ? 'https://example.com/${number + 1}' : null,
  );
}

_FakeScraper _chain({int last = 50}) {
  final scraper = _FakeScraper();

  for (var number = 1; number <= last; number++) {
    scraper.chapters['https://example.com/$number'] = chapter(
      number,
      last: last,
    );
  }

  return scraper;
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

PrefetchController _buildController({
  required _FakeScraper scraper,
  required _FakeStore store,
  ReadNovel? Function()? seedOf,
}) {
  return PrefetchController(
    novelKey: novel.key,
    seedOf: seedOf ?? () => novel,
    scraper: scraper,
    store: store,
  );
}

void main() {
  test('the first batch saves ten chapters from the last read one', () async {
    final scraper = _chain();
    final store = _FakeStore();
    final controller = _buildController(scraper: scraper, store: store);
    await settle();

    await controller.fetchNextBatch();

    expect(scraper.requests, hasLength(10));
    expect(scraper.requests.first, 'https://example.com/1');
    expect(store.novels[novel.key], hasLength(10));
    expect(controller.state.savedCount, 10);
    expect(controller.state.savedTitles.first, 'Chapter 1');
    expect(controller.state.fetchedCount, 10);
    expect(controller.state.hasNextBatch, isTrue);
    expect(controller.state.isFetching, isFalse);
    expect(controller.state.error, isNull);
    expect(controller.state.buttonLabel, 'Get next 10 chapters');
  });

  test('the next batch continues after the saved chapters', () async {
    final scraper = _chain();
    final store = _FakeStore();
    final controller = _buildController(scraper: scraper, store: store);
    await settle();

    await controller.fetchNextBatch();
    await controller.fetchNextBatch();

    expect(scraper.requests, hasLength(20));
    expect(scraper.requests[10], 'https://example.com/11');
    expect(store.novels[novel.key], hasLength(20));
    expect(controller.state.savedCount, 20);
    expect(controller.state.fetchedCount, 10);
    expect(controller.state.hasNextBatch, isTrue);
  });

  test('a finished novel stops the button', () async {
    final scraper = _chain(last: 4);
    final store = _FakeStore();
    final controller = _buildController(scraper: scraper, store: store);
    await settle();

    await controller.fetchNextBatch();

    expect(controller.state.savedCount, 4);
    expect(controller.state.hasNextBatch, isFalse);

    final requests = List<String>.of(scraper.requests);
    await controller.fetchNextBatch();

    expect(scraper.requests, requests);
    expect(controller.state.savedCount, 4);
    expect(controller.state.isFetching, isFalse);
  });

  test('a failed fetch keeps the chapters saved so far', () async {
    final scraper = _chain()..failOnRequest = 3;
    final store = _FakeStore();
    final controller = _buildController(scraper: scraper, store: store);
    await settle();

    await controller.fetchNextBatch();

    expect(controller.state.savedCount, 2);
    expect(controller.state.isFetching, isFalse);
    expect(controller.state.error, 'Network is down');
    expect(controller.state.hasNextBatch, isTrue);
    expect(store.novels[novel.key], hasLength(2));

    scraper.failOnRequest = null;
    await controller.fetchNextBatch();

    expect(controller.state.savedCount, 12);
    expect(scraper.requests[3], 'https://example.com/3');
    expect(controller.state.error, isNull);
    expect(controller.state.hasNextBatch, isTrue);
  });

  test('a storage failure surfaces as an error', () async {
    final scraper = _chain();
    final store = _FakeStore()..failSave = true;
    final controller = _buildController(scraper: scraper, store: store);
    await settle();

    await controller.fetchNextBatch();

    expect(controller.state.error, 'Disk full');
    expect(controller.state.savedCount, 0);
    expect(controller.state.isFetching, isFalse);
    expect(controller.state.hasNextBatch, isTrue);
  });

  test('a reopened controller reports the saved chapters', () async {
    final scraper = _chain();
    final store = _FakeStore();

    for (var number = 1; number <= 3; number++) {
      await store.save(novel.key, chapter(number));
    }

    final controller = _buildController(scraper: scraper, store: store);
    await settle();

    expect(controller.state.ready, isTrue);
    expect(controller.state.savedCount, 3);
    expect(controller.state.savedTitles, <String>[
      'Chapter 1',
      'Chapter 2',
      'Chapter 3',
    ]);
    expect(controller.state.buttonLabel, 'Get next 10 chapters');

    await controller.fetchNextBatch();

    expect(scraper.requests.first, 'https://example.com/4');
    expect(controller.state.savedCount, 13);
    expect(controller.state.fetchedCount, 10);
  });

  test('a finished novel stays finished after reopening', () async {
    final scraper = _chain(last: 4);
    final store = _FakeStore();

    for (var number = 1; number <= 4; number++) {
      await store.save(novel.key, chapter(number, last: 4));
    }

    final controller = _buildController(scraper: scraper, store: store);
    await settle();

    expect(controller.state.savedCount, 4);
    expect(controller.state.hasNextBatch, isFalse);

    await controller.fetchNextBatch();

    expect(scraper.requests, isEmpty);
    expect(controller.state.savedCount, 4);
  });

  test('without a seed chapter the fetch reports a missing start', () async {
    final scraper = _chain();
    final store = _FakeStore();
    final controller = PrefetchController(
      novelKey: novel.key,
      seedOf: () => null,
      scraper: scraper,
      store: store,
    );
    await settle();

    await controller.fetchNextBatch();

    expect(controller.state.error, 'No chapter to start from.');
    expect(controller.state.savedCount, 0);
    expect(scraper.requests, isEmpty);
  });

  test('the batch starts at the chapter being read right now', () async {
    final scraper = _chain();
    final store = _FakeStore();
    var current = novel;

    final controller = _buildController(
      scraper: scraper,
      store: store,
      seedOf: () => current,
    );
    await settle();

    // The reader moves on before the first batch is saved.
    current = readingAt(5);

    await controller.fetchNextBatch();

    expect(scraper.requests.first, 'https://example.com/5');
    expect(scraper.requests, hasLength(10));
    expect(controller.state.savedCount, 10);
    expect(controller.state.savedTitles.first, 'Chapter 5');
    expect(controller.state.savedTitles.last, 'Chapter 14');
  });

  test('a saved run behind the reading position jumps forward', () async {
    final scraper = _chain();
    final store = _FakeStore();

    for (var number = 1; number <= 3; number++) {
      await store.save(novel.key, chapter(number));
    }

    final controller = _buildController(
      scraper: scraper,
      store: store,
      seedOf: () => readingAt(20),
    );
    await settle();

    await controller.fetchNextBatch();

    expect(scraper.requests.first, 'https://example.com/20');
    expect(controller.state.savedCount, 13);
    expect(controller.state.savedTitles.last, 'Chapter 29');
    expect(controller.state.hasNextBatch, isTrue);
  });

  test('chapters that are already saved are not fetched again', () async {
    final scraper = _chain();
    final store = _FakeStore();

    for (var number = 5; number <= 7; number++) {
      await store.save(novel.key, chapter(number));
    }

    final controller = _buildController(
      scraper: scraper,
      store: store,
      seedOf: () => readingAt(2),
    );
    await settle();

    await controller.fetchNextBatch();

    // 2, 3, 4 and then straight past the saved run to 8.
    expect(scraper.requests, <String>[
      'https://example.com/2',
      'https://example.com/3',
      'https://example.com/4',
      'https://example.com/8',
      'https://example.com/9',
      'https://example.com/10',
      'https://example.com/11',
      'https://example.com/12',
      'https://example.com/13',
      'https://example.com/14',
    ]);
    expect(controller.state.savedCount, 13);
    expect(controller.state.savedTitles, hasLength(13));
    expect(controller.state.savedTitles.toSet(), hasLength(13));
  });
}
