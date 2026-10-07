import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/novels/domain/models/read_novel.dart';
import 'package:novel_reader/features/novels/presentation/providers/read_novels_provider.dart';
import 'package:novel_reader/features/scraper/domain/models/manhwa_series.dart';
import 'package:novel_reader/features/scraper/presentation/providers/manhwa_shelf_provider.dart';
import 'package:novel_reader/features/translation/domain/services/translation_service.dart';
import 'package:novel_reader/features/translation/presentation/providers/translation_providers.dart';

class _FakeTranslation implements TranslationService {
  _FakeTranslation({this.fail = false});

  final bool fail;
  int calls = 0;

  @override
  Future<List<String>> translateParagraphs(
    List<String> paragraphs, {
    required String targetLanguage,
  }) async {
    calls += 1;

    if (fail) {
      throw TranslationException('offline');
    }

    return [for (final text in paragraphs) 'EN($text)'];
  }
}

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  ReadNovelsController controller() =>
      container.read(readNovelsProvider.notifier);

  test('record keeps one entry per novel, keyed by name', () async {
    await controller().record(
      'https://site.com/nova/chapter-1',
      'Chapter 1',
      novelTitle: 'Nova',
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await controller().record(
      'https://site.com/nova/chapter-2?x=1',
      'Chapter 2',
      novelTitle: 'Nova',
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await controller().record(
      'https://site.com/sol/chapter-9',
      'Chapter 9',
      novelTitle: 'Sol',
    );

    final list = await container.read(readNovelsProvider.future);

    expect(list, hasLength(2));
    expect(list.map((entry) => entry.title), ['Sol', 'Nova']);

    final nova = list.singleWhere(
      (entry) => entry.key == 'novel:site.com:Nova',
    );
    expect(nova.url, 'https://site.com/nova/chapter-2?x=1');
    expect(nova.chapterTitle, 'Chapter 2');
    expect(nova.novelTitle, 'Nova');
  });

  test('two novels from the same site stay separate', () async {
    await controller().record(
      'https://site.com/novel/chapter-1',
      'Chapter 1',
      novelTitle: 'Alpha',
    );
    await controller().record(
      'https://site.com/other/chapter-1',
      'Chapter 1',
      novelTitle: 'Beta',
    );

    final list = await container.read(readNovelsProvider.future);

    expect(list, hasLength(2));
    expect(list.map((entry) => entry.title).toSet(), {'Alpha', 'Beta'});
    expect(list.map((entry) => entry.key).toSet(), {
      'novel:site.com:Alpha',
      'novel:site.com:Beta',
    });
  });

  test('entries without a novel name fall back to a URL key', () async {
    await controller().record('https://site.com/nova/chapter-1', 'Chapter 1');

    final list = await container.read(readNovelsProvider.future);

    expect(list, hasLength(1));
    expect(list.single.key, 'url:site.com:nova');
    expect(list.single.title, 'Chapter 1');
    expect(list.single.novelTitle, isNull);
  });

  test('preserves the position when the same chapter reopens', () async {
    await controller().record(
      'https://site.com/nova/chapter-2',
      'Chapter 2',
      novelTitle: 'Nova',
      paragraphIndex: 40,
    );
    await controller().record(
      'https://site.com/nova/chapter-2',
      'Chapter 2',
      novelTitle: 'Nova',
    );

    final list = await container.read(readNovelsProvider.future);

    expect(list, hasLength(1));
    expect(list.single.paragraphIndex, 40);
  });

  test('resets the position when another chapter opens', () async {
    await controller().record(
      'https://site.com/nova/chapter-2',
      'Chapter 2',
      novelTitle: 'Nova',
      paragraphIndex: 40,
    );
    await controller().record(
      'https://site.com/nova/chapter-3',
      'Chapter 3',
      novelTitle: 'Nova',
    );

    final list = await container.read(readNovelsProvider.future);

    expect(list, hasLength(1));
    expect(list.single.url, 'https://site.com/nova/chapter-3');
    expect(list.single.paragraphIndex, 0);
  });

  test('an explicit position report updates the entry', () async {
    await controller().record(
      'https://site.com/nova/chapter-2',
      'Chapter 2',
      novelTitle: 'Nova',
      paragraphIndex: 3,
    );
    await controller().record(
      'https://site.com/nova/chapter-2',
      'Chapter 2',
      novelTitle: 'Nova',
      paragraphIndex: 17,
    );

    final list = await container.read(readNovelsProvider.future);

    expect(list.single.paragraphIndex, 17);
  });

  test('a picture series is keyed by its shelf key and folds the '
      'chapters it recorded earlier', () async {
    await controller().record(
      'https://site.com/manga/nova/chapter-1',
      'Chapter 1',
    );
    await controller().record(
      'https://site.com/manga/nova/chapter-2',
      'Chapter 2',
      manhwaKey: 'manhwa:site.com/manga/nova',
      paragraphIndex: 3,
      paragraphCount: 7,
    );

    final list = await container.read(readNovelsProvider.future);

    expect(list, hasLength(1));

    final nova = list.single;
    expect(nova.key, 'manhwa:site.com/manga/nova');
    expect(nova.isManhwa, isTrue);
    expect(nova.url, 'https://site.com/manga/nova/chapter-2');
    expect(nova.hasRead('https://site.com/manga/nova/chapter-1'), isTrue);
    expect(nova.hasRead('https://site.com/manga/nova/chapter-2'), isTrue);

    // The chapter read before its length was tracked has no share yet.
    expect(nova.readPercent('https://site.com/manga/nova/chapter-1'), isNull);
    expect(nova.readPercent('https://site.com/manga/nova/chapter-2'), '50%');
  });

  test('two manhwa from one host never share an entry', () async {
    // Recorded before the shelf knew the series: the plain URL key
    // only sees the shared /manga/ folder both hang from.
    await controller().record(
      'https://site.com/manga/alpha/chapter-0',
      'Chapter 0',
    );

    final shelfController = container.read(manhwaSeriesProvider.notifier);
    await shelfController.record(
      ManhwaSeries(
        novelKey: 'manhwa:site.com/manga/alpha',
        title: 'Alpha',
        sourceUrl: 'https://site.com/manga/alpha',
        openedAt: DateTime(2026),
      ),
    );
    await shelfController.record(
      ManhwaSeries(
        novelKey: 'manhwa:site.com/manga/beta',
        title: 'Beta',
        sourceUrl: 'https://site.com/manga/beta',
        openedAt: DateTime(2026),
      ),
    );

    await controller().record(
      'https://site.com/manga/alpha/chapter-1',
      'Chapter 1',
    );
    await controller().record(
      'https://site.com/manga/beta/chapter-1',
      'Chapter 1',
    );

    final list = await container.read(readNovelsProvider.future);

    expect(list, hasLength(2));
    expect(list.map((entry) => entry.key).toSet(), {
      'manhwa:site.com/manga/alpha',
      'manhwa:site.com/manga/beta',
    });
    expect(list.map((entry) => entry.url).toSet(), {
      'https://site.com/manga/alpha/chapter-1',
      'https://site.com/manga/beta/chapter-1',
    });

    final alpha = list.singleWhere(
      (entry) => entry.key == 'manhwa:site.com/manga/alpha',
    );
    expect(alpha.title, 'Alpha');

    // The chapter read before the shelf knew the series folded in.
    expect(alpha.hasRead('https://site.com/manga/alpha/chapter-0'), isTrue);
    expect(alpha.hasRead('https://site.com/manga/beta/chapter-0'), isFalse);
  });

  test('records how far into each chapter the reader got', () async {
    await controller().record(
      'https://site.com/nova/chapter-1',
      'Chapter 1',
      novelTitle: 'Nova',
      paragraphIndex: 4,
      paragraphCount: 11,
    );
    await controller().record(
      'https://site.com/nova/chapter-2',
      'Chapter 2',
      novelTitle: 'Nova',
      paragraphIndex: 0,
      paragraphCount: 10,
    );

    final nova = (await container.read(readNovelsProvider.future)).single;

    expect(nova.hasRead('https://site.com/nova/chapter-1'), isTrue);
    expect(nova.readPercent('https://site.com/nova/chapter-1'), '40%');
    expect(nova.readPercent('https://site.com/nova/chapter-2'), '0%');
    expect(nova.readPercent('https://site.com/nova/chapter-3'), isNull);

    expect(nova.paragraphIndex, 0);
    expect(nova.paragraphCount, 10);
  });

  test('a one-paragraph chapter counts as fully read', () async {
    await controller().record(
      'https://site.com/one/chapter-1',
      'Chapter 1',
      novelTitle: 'One',
      paragraphIndex: 0,
      paragraphCount: 1,
    );

    final one = (await container.read(readNovelsProvider.future)).single;

    expect(one.readFraction('https://site.com/one/chapter-1'), 1.0);
    expect(one.readPercent('https://site.com/one/chapter-1'), '100%');
  });

  test('readEntryFor finds a series by its shelf key', () {
    final entries = [
      ReadNovel(
        key: 'url:site.com:manga',
        url: 'https://site.com/manga/nova/chapter-1',
        chapterTitle: 'Chapter 1',
        readAt: DateTime(2026),
      ),
    ];

    expect(readEntryFor(entries, 'manhwa:site.com/manga/nova'), entries.single);
    expect(readEntryFor(entries, 'manhwa:site.com/manga'), entries.single);
    expect(readEntryFor(entries, 'manhwa:site.com/manga/other'), isNull);
    expect(readEntryFor(entries, 'novel:site.com:Nova'), isNull);
    expect(readEntryFor(const [], 'manhwa:site.com/manga/nova'), isNull);
  });

  test('the novels list leaves shelf series to the manhwa page', () async {
    await controller().record(
      'https://site.com/nova/chapter-1',
      'Chapter 1',
      novelTitle: 'Nova',
    );
    await controller().record(
      'https://site.com/manga/nova/chapter-1',
      'Chapter 1',
    );
    await controller().record(
      'https://site.com/manga/other/chapter-1',
      'Chapter 1',
      manhwaKey: 'manhwa:site.com/manga/other',
    );

    await container
        .read(manhwaSeriesProvider.notifier)
        .record(
          ManhwaSeries(
            novelKey: 'manhwa:site.com/manga/nova',
            title: 'Nova',
            sourceUrl: 'https://site.com/manga/nova',
            openedAt: DateTime(2026),
          ),
        );

    final history = container.read(novelHistoryProvider);

    expect(history.hasValue, isTrue);
    expect(history.value!.map((entry) => entry.key), ['novel:site.com:Nova']);
  });

  test('remove deletes the matching entry', () async {
    await controller().record(
      'https://site.com/nova/chapter-1',
      'Chapter 1',
      novelTitle: 'Nova',
    );
    await controller().record(
      'https://other.org/sol/chapter-1',
      'Other',
      novelTitle: 'Sol',
    );

    await controller().remove('novel:site.com:Nova');

    final list = await container.read(readNovelsProvider.future);
    expect(list, hasLength(1));
    expect(list.single.key, 'novel:other.org:Sol');
  });

  test('remove of an unknown key is a no-op', () async {
    await controller().record(
      'https://site.com/nova/chapter-1',
      'Chapter 1',
      novelTitle: 'Nova',
    );

    await controller().remove('missing');

    final list = await container.read(readNovelsProvider.future);
    expect(list, hasLength(1));
  });

  test('removeSeries clears every entry of that series', () async {
    await controller().record(
      'https://asurascans.com/comics/myst-might-mayhem-bd5bdaf8/chapter/116',
      'Chapter 116',
      manhwaKey: 'manhwa:asurascans.com/comics/myst-might-mayhem-bd5bdaf8',
    );
    // The same chapter before it was keyed to the shelf.
    await controller().record(
      'https://asurascans.com/comics/myst-might-mayhem-bd5bdaf8/chapter/115',
      'Chapter 115',
    );
    await controller().record(
      'https://site.com/nova/chapter-1',
      'Chapter 1',
      novelTitle: 'Nova',
    );

    await controller().removeSeries(
      'manhwa:asurascans.com/comics/myst-might-mayhem-bd5bdaf8',
    );

    final list = await container.read(readNovelsProvider.future);

    expect(list.map((entry) => entry.key), ['novel:site.com:Nova']);
  });

  test('removeSeries of a series nobody opened is a no-op', () async {
    await controller().record(
      'https://site.com/nova/chapter-1',
      'Chapter 1',
      novelTitle: 'Nova',
    );

    await controller().removeSeries('manhwa:site.com/nowhere');

    final list = await container.read(readNovelsProvider.future);
    expect(list, hasLength(1));
  });

  test('CJK titles get English translations for display', () async {
    final fake = _FakeTranslation();
    final scoped = ProviderContainer(
      overrides: [translationServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(scoped.dispose);

    await scoped
        .read(readNovelsProvider.notifier)
        .record(
          'https://site.com/n/ch-1',
          '第4682章 十小聖之首',
          novelTitle: '開局簽到荒古聖體',
        );

    final list = await scoped.read(readNovelsProvider.future);
    final entry = list.single;

    expect(entry.title, 'EN(開局簽到荒古聖體)');
    expect(entry.displayChapterTitle, 'EN(第4682章 十小聖之首)');

    expect(entry.novelTitle, '開局簽到荒古聖體');
    expect(entry.chapterTitle, '第4682章 十小聖之首');
    expect(entry.key, 'novel:site.com:開局簽到荒古聖體');
    expect(fake.calls, 1);

    await scoped
        .read(readNovelsProvider.notifier)
        .record(
          'https://site.com/n/ch-1',
          '第4682章 十小聖之首',
          novelTitle: '開局簽到荒古聖體',
          paragraphIndex: 9,
        );

    final updated = await scoped.read(readNovelsProvider.future);
    expect(updated.single.novelTitleEn, 'EN(開局簽到荒古聖體)');
    expect(updated.single.chapterTitleEn, 'EN(第4682章 十小聖之首)');
    expect(updated.single.paragraphIndex, 9);
    expect(fake.calls, 1);
  });

  test('failed title translation falls back to the original', () async {
    final scoped = ProviderContainer(
      overrides: [
        translationServiceProvider.overrideWithValue(
          _FakeTranslation(fail: true),
        ),
      ],
    );
    addTearDown(scoped.dispose);

    await scoped
        .read(readNovelsProvider.notifier)
        .record(
          'https://site.com/n/ch-1',
          '第4682章 十小聖之首',
          novelTitle: '開局簽到荒古聖體',
        );

    final entry = (await scoped.read(readNovelsProvider.future)).single;

    expect(entry.novelTitleEn, isNull);
    expect(entry.chapterTitleEn, isNull);
    expect(entry.title, '開局簽到荒古聖體');
    expect(entry.displayChapterTitle, '第4682章 十小聖之首');
  });

  test('keyForNovel uses host and novel name', () {
    expect(
      ReadNovel.keyForNovel(
        'https://www.site.com/novel/chapter-3?q=1',
        'My Novel',
      ),
      'novel:www.site.com:My Novel',
    );
  });

  test('keyFor falls back to host and first path segment', () {
    expect(
      ReadNovel.keyFor('https://www.site.com/novel-slug/chapter-3?q=1#top'),
      'url:www.site.com:novel-slug',
    );
    expect(
      ReadNovel.keyFor('https://www.site.com/index.html'),
      'url:www.site.com:index.html',
    );
    expect(ReadNovel.keyFor('https://www.site.com/'), 'url:www.site.com');
  });

  test('json round trip preserves fields', () {
    final entry = ReadNovel(
      key: 'novel:site.com:Nova',
      url: 'https://site.com/nova/chapter-2',
      novelTitle: 'Nova',
      novelTitleEn: 'Nova EN',
      chapterTitle: 'Chapter 2',
      chapterTitleEn: 'Chapter 2 EN',
      paragraphIndex: 17,
      paragraphCount: 19,
      chapterProgress: const {
        'https://site.com/nova/chapter-1': [5, 9],
        'https://site.com/nova/chapter-2': [17, 19],
      },
      readAt: DateTime.fromMillisecondsSinceEpoch(1735689600000),
    );

    final decoded = ReadNovel.fromJson(
      jsonDecode(jsonEncode(entry.toJson())) as Map<String, Object?>,
    );

    expect(decoded.key, entry.key);
    expect(decoded.url, entry.url);
    expect(decoded.novelTitle, 'Nova');
    expect(decoded.novelTitleEn, 'Nova EN');
    expect(decoded.chapterTitle, 'Chapter 2');
    expect(decoded.chapterTitleEn, 'Chapter 2 EN');
    expect(decoded.title, 'Nova EN');
    expect(decoded.displayChapterTitle, 'Chapter 2 EN');
    expect(decoded.paragraphIndex, 17);
    expect(decoded.paragraphCount, 19);
    expect(decoded.chapterProgress, entry.chapterProgress);
    expect(decoded.readAt, entry.readAt);
    expect(decoded.host, 'site.com');
  });

  test('legacy entries with a single title field still load', () {
    final decoded = ReadNovel.fromJson({
      'key': 'url:site.com:nova',
      'url': 'https://site.com/nova/chapter-1',
      'title': 'Chapter 1',
      'readAt': 1735689600000,
    });

    expect(decoded.novelTitle, isNull);
    expect(decoded.novelTitleEn, isNull);
    expect(decoded.chapterTitle, 'Chapter 1');
    expect(decoded.chapterTitleEn, isNull);
    expect(decoded.title, 'Chapter 1');
    expect(decoded.paragraphIndex, 0);
    expect(decoded.paragraphCount, 0);
    expect(decoded.chapterProgress, isEmpty);
    expect(decoded.isManhwa, isFalse);
  });
}
