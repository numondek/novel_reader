import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/scraper/domain/models/manhwa_series.dart';
import 'package:novel_reader/features/scraper/presentation/providers/manhwa_shelf_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

ManhwaSeries _series(String novelKey, String title) {
  return ManhwaSeries(
    novelKey: novelKey,
    title: title,
    sourceUrl: 'https://site.com/$novelKey',
    coverUrl: 'https://site.com/cover.jpg',
    openedAt: DateTime(2026),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    tempDir = Directory.systemTemp.createTempSync('novel_reader_test');

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

  test('the shelf survives a container restart', () async {
    final first = ProviderContainer();

    await first
        .read(manhwaSeriesProvider.notifier)
        .record(_series('manhwa:site.com/manga/demo', 'Grid Demo'));
    await first.read(manhwaSeriesProvider.future);

    // Simulates closing the app: everything must live in prefs.
    first.dispose();

    final second = ProviderContainer();
    addTearDown(second.dispose);

    final list = await second.read(manhwaSeriesProvider.future);

    expect(list, hasLength(1));
    expect(list.single.novelKey, 'manhwa:site.com/manga/demo');
    expect(list.single.title, 'Grid Demo');
    expect(list.single.coverUrl, 'https://site.com/cover.jpg');
  });

  test('reopening a series keeps one entry, newest first', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(manhwaSeriesProvider.notifier);

    await controller.record(_series('manhwa:site.com/manga/first', 'First'));
    await controller.record(_series('manhwa:site.com/manga/second', 'Second'));
    await controller.record(_series('manhwa:site.com/manga/first', 'First'));
    await container.read(manhwaSeriesProvider.future);

    final list = await container.read(manhwaSeriesProvider.future);

    expect(list.map((entry) => entry.title), ['First', 'Second']);
  });
}
