import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/network/dio_client.dart';
import 'package:novel_reader/features/prefetch/data/services/app_database_offline_chapter_store.dart';
import 'package:novel_reader/features/scraper/domain/models/extracted_chapter.dart';
import 'package:novel_reader/features/scraper/domain/services/offline_image_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

ExtractedChapter chapter(String url, {required String title}) {
  return ExtractedChapter(title: title, paragraphs: const ['Text.'], url: url);
}

ExtractedChapter pictureChapter(String url) {
  return ExtractedChapter(
    title: 'Chapter 1',
    paragraphs: const [],
    url: url,
    imageUrls: ['$url/1.jpg', '$url/2.jpg'],
  );
}

class _FakeImageStore implements OfflineImageStore {
  _FakeImageStore({this.failAll = false, this.failUrls = const {}});

  final List<String> saved = [];
  final List<String?> referers = [];
  bool failAll;
  final Set<String> failUrls;

  @override
  Future<String> save(String url, {String? referer}) async {
    referers.add(referer);

    if (failAll || failUrls.contains(url)) {
      throw Exception('Image blocked');
    }

    saved.add(url);
    return '/offline/${url.hashCode}.jpg';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('novel_reader_store_test');

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

  test('count stays at zero until a chapter is saved', () async {
    final store = AppDatabaseOfflineChapterStore();

    expect(await store.count('novel:site.com:Nova'), 0);
  });

  test('count follows the manifest and ignores other novels', () async {
    final store = AppDatabaseOfflineChapterStore();

    await store.save(
      'novel:site.com:Nova',
      chapter('https://site.com/1', title: 'One'),
    );
    await store.save(
      'novel:site.com:Nova',
      chapter('https://site.com/2', title: 'Two'),
    );
    await store.save(
      'novel:site.com:Nova',
      chapter('https://site.com/2', title: 'Two'),
    );
    await store.save(
      'novel:other.org:Sol',
      chapter('https://other.org/1', title: 'Solo'),
    );

    expect(await store.count('novel:site.com:Nova'), 2);
    expect(await store.count('novel:other.org:Sol'), 1);
    expect(await store.count('novel:never.org:Ghost'), 0);
  });

  test('saved chapters load in reading order for the list', () async {
    final store = AppDatabaseOfflineChapterStore();

    await store.save(
      'novel:site.com:Nova',
      chapter('https://site.com/1', title: 'One'),
    );
    await store.save(
      'novel:site.com:Nova',
      chapter('https://site.com/2', title: 'Two'),
    );

    final loaded = await store.load('novel:site.com:Nova');

    expect([for (final saved in loaded) saved.title], ['One', 'Two']);
  });

  test('a fresh store reads what an earlier one saved', () async {
    final first = AppDatabaseOfflineChapterStore();
    await first.save(
      'novel:site.com:Nova',
      chapter('https://site.com/1', title: 'One'),
    );

    final second = AppDatabaseOfflineChapterStore();

    expect(await second.count('novel:site.com:Nova'), 1);
    expect((await second.load('novel:site.com:Nova')).single.title, 'One');
  });

  test(
    'a picture chapter downloads its images before it is recorded',
    () async {
      final images = _FakeImageStore();
      final store = AppDatabaseOfflineChapterStore(images: images);

      await store.save(
        'manhwa:site.com:Demo',
        pictureChapter('https://site.com/ch-1'),
      );

      expect(images.saved, [
        'https://site.com/ch-1/1.jpg',
        'https://site.com/ch-1/2.jpg',
      ]);
      expect(images.referers, [
        'https://site.com/ch-1',
        'https://site.com/ch-1',
      ]);

      final saved = await store.find('https://site.com/ch-1');
      expect(saved, isNotNull);
      expect(saved!.offlineImagePaths, hasLength(2));
      expect(saved.offlineImagePaths!.every((path) => path != null), isTrue);
      expect(await store.count('manhwa:site.com:Demo'), 1);
    },
  );

  test('a chapter whose images all fail is not saved', () async {
    final store = AppDatabaseOfflineChapterStore(
      images: _FakeImageStore(failAll: true),
    );

    await expectLater(
      store.save(
        'manhwa:site.com:Demo',
        pictureChapter('https://site.com/ch-1'),
      ),
      throwsA(
        isA<PageFetchException>().having(
          (error) => error.message,
          'message',
          contains('Could not download the chapter pictures.'),
        ),
      ),
    );

    expect(await store.count('manhwa:site.com:Demo'), 0);
    expect(await store.find('https://site.com/ch-1'), isNull);
  });

  test('a partially downloaded chapter keeps the pictures it got', () async {
    final images = _FakeImageStore(failUrls: {'https://site.com/ch-1/2.jpg'});
    final store = AppDatabaseOfflineChapterStore(images: images);

    await store.save(
      'manhwa:site.com:Demo',
      pictureChapter('https://site.com/ch-1'),
    );

    final saved = await store.find('https://site.com/ch-1');

    expect(saved!.offlineImagePaths, hasLength(2));
    expect(saved.offlineImagePaths!.first, isNotNull);
    expect(saved.offlineImagePaths!.last, isNull);
    expect(await store.count('manhwa:site.com:Demo'), 1);
  });

  test('remove takes every chapter of that novel with it', () async {
    final store = AppDatabaseOfflineChapterStore();

    await store.save(
      'novel:site.com:Nova',
      chapter('https://site.com/1', title: 'One'),
    );
    await store.save(
      'novel:site.com:Nova',
      chapter('https://site.com/2', title: 'Two'),
    );
    await store.save(
      'novel:other.org:Sol',
      chapter('https://other.org/1', title: 'Solo'),
    );

    await store.remove('novel:site.com:Nova');

    expect(await store.count('novel:site.com:Nova'), 0);
    expect(await store.load('novel:site.com:Nova'), isEmpty);
    expect(await store.find('https://site.com/1'), isNull);
    expect(await store.find('https://site.com/2'), isNull);

    // What another novel saved stays where it was.
    expect(await store.count('novel:other.org:Sol'), 1);
    expect(await store.find('https://other.org/1'), isNotNull);
  });

  test('a chapter two novels list survives the first delete', () async {
    final store = AppDatabaseOfflineChapterStore();

    // The same chapter read under two keys: once as a novel, once
    // from the shelf.
    await store.save(
      'novel:site.com:Nova',
      chapter('https://site.com/1', title: 'One'),
    );
    await store.save(
      'manhwa:site.com/nova',
      chapter('https://site.com/1', title: 'One'),
    );

    await store.remove('novel:site.com:Nova');

    expect(await store.count('novel:site.com:Nova'), 0);
    expect(await store.count('manhwa:site.com/nova'), 1);
    expect(await store.find('https://site.com/1'), isNotNull);
  });

  test('removing a novel nothing was saved for is a no-op', () async {
    final store = AppDatabaseOfflineChapterStore();

    await store.remove('novel:site.com:Nobody');

    expect(await store.count('novel:site.com:Nobody'), 0);
  });
}
