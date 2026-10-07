import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/settings/presentation/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    tempDir = Directory.systemTemp.createTempSync('novel_reader_settings');

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

  test('dark mode stored on disk is loaded on start', () async {
    SharedPreferences.setMockInitialValues({
      'novel_reader.db:settings.dark_mode': true,
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(settingsProvider);
    await pumpEventQueue();

    expect(container.read(settingsProvider).darkMode, isTrue);
  });

  test('toggling dark mode survives a restart', () async {
    final first = ProviderContainer();
    addTearDown(first.dispose);

    await first.read(settingsProvider.notifier).setDarkMode(true);
    await pumpEventQueue();

    expect(first.read(settingsProvider).darkMode, isTrue);

    // A fresh container reads what the first one wrote to storage.
    final second = ProviderContainer();
    addTearDown(second.dispose);

    second.read(settingsProvider);
    await pumpEventQueue();

    expect(second.read(settingsProvider).darkMode, isTrue);
  });
}
