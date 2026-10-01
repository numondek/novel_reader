import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/novels/presentation/providers/read_novels_provider.dart';
import 'package:novel_reader/features/translation/domain/services/translation_service.dart';
import 'package:novel_reader/features/translation/presentation/providers/translation_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTranslation implements TranslationService {
  @override
  Future<List<String>> translateParagraphs(
    List<String> paragraphs, {
    required String targetLanguage,
  }) async {
    return [for (final text in paragraphs) 'EN($text)'];
  }
}

const _pathProviderChannel =
    MethodChannel('plugins.flutter.io/path_provider');

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

  test(
    'read novels and position survive a container restart',
    () async {
      final first = ProviderContainer(
        overrides: [
          translationServiceProvider.overrideWithValue(_FakeTranslation()),
        ],
      );

      await first
          .read(readNovelsProvider.notifier)
          .record(
            'https://site.com/n/ch-1',
            '第4682章 十小聖之首',
            novelTitle: '開局簽到荒古聖體',
          );
      await first
          .read(readNovelsProvider.notifier)
          .record(
            'https://site.com/n/ch-1',
            '第4682章 十小聖之首',
            novelTitle: '開局簽到荒古聖體',
            paragraphIndex: 17,
          );
      await first.read(readNovelsProvider.future);

      // Simulates closing the app: everything must live in prefs.
      first.dispose();

      final second = ProviderContainer();
      addTearDown(second.dispose);

      final list = await second.read(readNovelsProvider.future);

      expect(list, hasLength(1));
      expect(list.single.novelTitle, '開局簽到荒古聖體');
      expect(list.single.novelTitleEn, 'EN(開局簽到荒古聖體)');
      expect(list.single.chapterTitle, '第4682章 十小聖之首');
      expect(list.single.chapterTitleEn, 'EN(第4682章 十小聖之首)');
      expect(list.single.title, 'EN(開局簽到荒古聖體)');
      expect(list.single.paragraphIndex, 17);
      expect(list.single.url, 'https://site.com/n/ch-1');
    },
  );
}
