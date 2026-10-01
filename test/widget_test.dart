import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_reader/app/app.dart';

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
}
