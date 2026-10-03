import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/library/presentation/providers/pdf_library_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File source;

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    tempDir = Directory.systemTemp.createTempSync('novel_reader_test');
    source = File('${tempDir.path}${Platform.pathSeparator}source.pdf')
      ..writeAsStringSync('%PDF-1.4 fake');

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
    'an imported PDF and its position survive a container restart',
    () async {
      final first = ProviderContainer();

      final item = await first
          .read(pdfLibraryProvider.notifier)
          .add(sourcePath: source.path, fileName: 'A Great Tale.pdf');
      await first
          .read(pdfLibraryProvider.notifier)
          .savePosition(item.path, page: 7, pageCount: 12);
      await first.read(pdfLibraryProvider.future);

      // Simulates closing the app: the entry, the position and the
      // retained copy must all live on disk.
      first.dispose();

      expect(File(item.path).existsSync(), isTrue);

      final second = ProviderContainer();
      addTearDown(second.dispose);

      final list = await second.read(pdfLibraryProvider.future);

      expect(list, hasLength(1));
      expect(list.single.path, item.path);
      expect(list.single.title, 'A Great Tale');
      expect(list.single.lastPage, 7);
      expect(list.single.pageCount, 12);
      expect(File(list.single.path).existsSync(), isTrue);
    },
  );

  test('a damaged entry does not hide the rest of the library', () async {
    SharedPreferences.setMockInitialValues({
      'novel_reader.db:pdf_library':
          '[{"path":"/p/good.pdf","title":"Good","addedAt":2000,'
          '"lastPage":4,"pageCount":9},'
          '{"path":"/p/bad.pdf","title":"Bad","addedAt":"oops"}]',
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final list = await container.read(pdfLibraryProvider.future);

    expect(list, hasLength(1));
    expect(list.single.title, 'Good');
    expect(list.single.lastPage, 4);
  });
}
