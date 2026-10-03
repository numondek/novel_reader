import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/prefetch/data/services/app_database_offline_chapter_store.dart';
import 'package:novel_reader/features/scraper/domain/models/extracted_chapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

ExtractedChapter chapter(String url, {required String title}) {
  return ExtractedChapter(title: title, paragraphs: const ['Text.'], url: url);
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
}
