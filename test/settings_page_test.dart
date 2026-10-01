import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/reader/domain/services/text_to_speech.dart';
import 'package:novel_reader/features/reader/presentation/providers/reader_tts_controller.dart';
import 'package:novel_reader/features/settings/presentation/pages/settings_page.dart';
import 'package:novel_reader/features/settings/presentation/providers/settings_provider.dart';

class _FakeTts implements TextToSpeech {
  String? spoken;

  @override
  Future<void> setLanguage(String language) async {}

  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  Future<void> setVoice(String name, String locale) async {}

  @override
  Future<List<TtsVoice>> getVoices() async => const [
        TtsVoice(name: 'Alice', locale: 'en-US'),
        TtsVoice(name: 'Bob', locale: 'zh-CN'),
        TtsVoice(name: 'Carol', locale: 'en-GB'),
      ];

  @override
  Future<void> speak(String text) async {
    spoken = text;
  }

  @override
  Future<void> stop() async {}

  @override
  void onCompletion(void Function() handler) {}

  @override
  void onCancel(void Function() handler) {}

  @override
  void onError(void Function(dynamic message) handler) {}
}

class _SeededSettings extends SettingsController {
  @override
  AppSettings build() {
    super.build();

    return const AppSettings(
      fontSize: 20,
      voiceName: 'Bob',
      voiceLocale: 'zh-CN',
    );
  }
}

Finder _dropdown() => find.byWidgetPredicate(
      (widget) => widget is DropdownButton,
    );

void main() {
  late _FakeTts fakeTts;

  Widget buildPage() {
    return ProviderScope(
      overrides: [
        ttsServiceProvider.overrideWithValue(fakeTts),
      ],
      child: const MaterialApp(home: SettingsPage()),
    );
  }

  ProviderContainer containerOf(WidgetTester tester) {
    return ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
  }

  setUp(() {
    fakeTts = _FakeTts();
  });

  testWidgets('shows reading and voice settings', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.text('Reading'), findsOneWidget);
    expect(find.text('Font size'), findsOneWidget);
    expect(find.text('18 px'), findsOneWidget);
    expect(find.text('Auto-scroll'), findsOneWidget);

    expect(
      find.text('Voice (Text-to-speech)'),
      findsOneWidget,
    );
    expect(find.text('Speech rate'), findsOneWidget);
    expect(find.text('0.50\u00d7'), findsOneWidget);
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('System default'), findsWidgets);
    expect(find.text('Test voice'), findsOneWidget);
  });

  testWidgets('auto-scroll switch updates settings',
      (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(containerOf(tester).read(settingsProvider).autoScroll, isTrue);

    await tester.tap(find.text('Auto-scroll'));
    await tester.pumpAndSettle();

    expect(
      containerOf(tester).read(settingsProvider).autoScroll,
      isFalse,
    );
  });

  testWidgets('speech rate slider updates settings', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    final sliders = find.byType(Slider);
    expect(sliders, findsNWidgets(2));

    await tester.drag(sliders.last, const Offset(240, 0));
    await tester.pumpAndSettle();

    expect(
      containerOf(tester).read(settingsProvider).speechRate,
      greaterThan(0.5),
    );
  });

  testWidgets('font size slider updates settings', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Slider).first, const Offset(240, 0));
    await tester.pumpAndSettle();

    expect(
      containerOf(tester).read(settingsProvider).fontSize,
      greaterThan(18),
    );
  });

  testWidgets('voice dropdown lists device voices and saves a pick',
      (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.text('Alice (en-US)'), findsNothing);

    await tester.tap(_dropdown());
    await tester.pumpAndSettle();

    expect(find.text('Alice (en-US)'), findsOneWidget);
    expect(find.text('Bob (zh-CN)'), findsOneWidget);
    expect(find.text('Carol (en-GB)'), findsOneWidget);

    await tester.tap(find.text('Alice (en-US)').last);
    await tester.pumpAndSettle();

    final settings = containerOf(tester).read(settingsProvider);
    expect(settings.voiceName, 'Alice');
    expect(settings.voiceLocale, 'en-US');
  });

  testWidgets('choosing system default clears the voice',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ttsServiceProvider.overrideWithValue(fakeTts),
          settingsProvider.overrideWith(_SeededSettings.new),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);

    await tester.tap(_dropdown());
    await tester.pumpAndSettle();

    await tester.tap(find.text('System default').last);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    final settings = container.read(settingsProvider);

    expect(settings.voiceName, isNull);
    expect(settings.voiceLocale, isNull);
    expect(find.text('System default'), findsWidgets);
  });
}
