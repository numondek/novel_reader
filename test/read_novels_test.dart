import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/novels/domain/models/read_novel.dart';
import 'package:novel_reader/features/novels/presentation/providers/read_novels_provider.dart';
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
    expect(
      list.map((entry) => entry.title),
      ['Sol', 'Nova'],
    );

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
    expect(
      list.map((entry) => entry.title).toSet(),
      {'Alpha', 'Beta'},
    );
    expect(
      list.map((entry) => entry.key).toSet(),
      {'novel:site.com:Alpha', 'novel:site.com:Beta'},
    );
  });

  test('entries without a novel name fall back to a URL key',
      () async {
    await controller().record(
      'https://site.com/nova/chapter-1',
      'Chapter 1',
    );

    final list = await container.read(readNovelsProvider.future);

    expect(list, hasLength(1));
    expect(list.single.key, 'url:site.com:nova');
    expect(list.single.title, 'Chapter 1');
    expect(list.single.novelTitle, isNull);
  });

  test('preserves the position when the same chapter reopens',
      () async {
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

  test('CJK titles get English translations for display', () async {
    final fake = _FakeTranslation();
    final scoped = ProviderContainer(
      overrides: [
        translationServiceProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(scoped.dispose);

    await scoped.read(readNovelsProvider.notifier).record(
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

    await scoped.read(readNovelsProvider.notifier).record(
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

  test('failed title translation falls back to the original',
      () async {
    final scoped = ProviderContainer(
      overrides: [
        translationServiceProvider.overrideWithValue(
          _FakeTranslation(fail: true),
        ),
      ],
    );
    addTearDown(scoped.dispose);

    await scoped.read(readNovelsProvider.notifier).record(
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
      ReadNovel.keyFor(
        'https://www.site.com/novel-slug/chapter-3?q=1#top',
      ),
      'url:www.site.com:novel-slug',
    );
    expect(
      ReadNovel.keyFor('https://www.site.com/index.html'),
      'url:www.site.com:index.html',
    );
    expect(
      ReadNovel.keyFor('https://www.site.com/'),
      'url:www.site.com',
    );
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
  });
}
