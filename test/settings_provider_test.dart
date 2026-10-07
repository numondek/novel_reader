import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/settings/presentation/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starts with sensible defaults', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final settings = container.read(settingsProvider);

    expect(settings.fontSize, 18);
    expect(settings.autoScroll, isTrue);
    expect(settings.speechRate, 0.5);
    expect(settings.voiceName, isNull);
    expect(settings.voiceLocale, isNull);
    expect(settings.autoScrollSpeed, 100);
  });

  test('setters update the state and clamp values', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(settingsProvider.notifier);

    await notifier.setFontSize(100);
    expect(container.read(settingsProvider).fontSize, 32);

    await notifier.setFontSize(1);
    expect(container.read(settingsProvider).fontSize, 14);

    await notifier.setAutoScroll(false);
    expect(container.read(settingsProvider).autoScroll, isFalse);

    await notifier.setSpeechRate(9);
    expect(container.read(settingsProvider).speechRate, 1.0);

    await notifier.setSpeechRate(0.01);
    expect(container.read(settingsProvider).speechRate, 0.1);

    await notifier.setVoice('Alice', 'en-US');
    expect(container.read(settingsProvider).voiceName, 'Alice');
    expect(container.read(settingsProvider).voiceLocale, 'en-US');

    await notifier.setVoice(null, null);
    expect(container.read(settingsProvider).voiceName, isNull);
    expect(container.read(settingsProvider).voiceLocale, isNull);

    await notifier.setAutoScrollSpeed(9999);
    expect(container.read(settingsProvider).autoScrollSpeed, 400);

    await notifier.setAutoScrollSpeed(1);
    expect(container.read(settingsProvider).autoScrollSpeed, 20);

    await notifier.setAutoScrollSpeed(250);
    expect(container.read(settingsProvider).autoScrollSpeed, 250);
  });

  group('persistence', () {
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

    test('settings survive a container restart', () async {
      final first = ProviderContainer();

      await first.read(settingsProvider.notifier).setFontSize(24);
      await first.read(settingsProvider.notifier).setAutoScroll(false);
      await first.read(settingsProvider.notifier).setSpeechRate(0.75);
      await first.read(settingsProvider.notifier).setVoice('Alice', 'en-US');
      await first.read(settingsProvider.notifier).setAutoScrollSpeed(250);

      first.dispose();

      final second = ProviderContainer();
      addTearDown(second.dispose);

      // build() returns defaults; the persisted values land right
      // after the async load finishes.
      second.read(settingsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final settings = second.read(settingsProvider);

      expect(settings.fontSize, 24);
      expect(settings.autoScroll, isFalse);
      expect(settings.speechRate, 0.75);
      expect(settings.voiceName, 'Alice');
      expect(settings.voiceLocale, 'en-US');
      expect(settings.autoScrollSpeed, 250);
    });
  });
}
