import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_reader/app/app.dart';
import 'package:novel_reader/features/settings/presentation/providers/settings_provider.dart';

class _DarkModeSettings extends SettingsController {
  @override
  AppSettings build() {
    super.build();

    return const AppSettings(darkMode: true);
  }
}

void main() {
  Widget app() => const ProviderScope(child: NovelFlowApp());

  testWidgets('splash transitions to home', (WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    expect(find.text('Novel Reader'), findsOneWidget);
    expect(find.text('Start reading'), findsOneWidget);
    expect(find.text('Novels'), findsOneWidget);
  });

  testWidgets('empty url shows snackbar', (WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a novel URL'), findsOneWidget);
  });

  testWidgets('the app theme follows the dark mode setting', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith(_DarkModeSettings.new)],
        child: const NovelFlowApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.darkTheme!.brightness, Brightness.dark);
  });
}
