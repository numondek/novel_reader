import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/utils/url_utils.dart';
import 'package:novel_reader/core/widgets/add_link_sheet.dart';

void main() {
  group('normalizeUrl', () {
    test('a pasted link without a scheme gains https', () {
      expect(
        normalizeUrl(' example.com/book/1 '),
        'https://example.com/book/1',
      );
    });

    test('a complete link is kept as it was pasted', () {
      expect(normalizeUrl('https://site.com/ch/2'), 'https://site.com/ch/2');
    });

    test('nothing usable leaves no link', () {
      expect(normalizeUrl(''), isNull);
      expect(normalizeUrl('   '), isNull);
      expect(normalizeUrl('https://'), isNull);
    });
  });

  group('AddLinkSheet', () {
    late String? result;

    Future<void> showSheet(WidgetTester tester) async {
      result = null;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder:
                (context) => Center(
                  child: FilledButton(
                    onPressed: () async {
                      result = await showAddLinkSheet(context);
                    },
                    child: const Text('open'),
                  ),
                ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(AddLinkSheet), findsOneWidget);
    }

    Future<void> submit(WidgetTester tester, String url) async {
      if (url.isNotEmpty) {
        await tester.enterText(find.byType(TextField), url);
      }

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
    }

    testWidgets('a link without a scheme is handed over complete', (
      tester,
    ) async {
      await showSheet(tester);

      await submit(tester, 'example.com/book/1');

      expect(result, 'https://example.com/book/1');
      expect(find.byType(AddLinkSheet), findsNothing);
    });

    testWidgets('an empty URL keeps the sheet open with a message', (
      tester,
    ) async {
      await showSheet(tester);

      await submit(tester, '');

      expect(find.byType(AddLinkSheet), findsOneWidget);
      expect(find.text('Enter a valid URL'), findsOneWidget);
      expect(result, isNull);
    });

    testWidgets('a link that cannot be opened keeps the sheet open', (
      tester,
    ) async {
      await showSheet(tester);

      await submit(tester, 'https://');

      expect(find.byType(AddLinkSheet), findsOneWidget);
      expect(find.text('Enter a valid URL'), findsOneWidget);
      expect(result, isNull);
    });

    testWidgets('typing again clears the message', (tester) async {
      await showSheet(tester);

      await submit(tester, 'https://');
      expect(find.text('Enter a valid URL'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'example.com');
      await tester.pump();

      expect(find.text('Enter a valid URL'), findsNothing);
    });

    testWidgets('dismissing the sheet adds nothing', (tester) async {
      await showSheet(tester);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(AddLinkSheet), findsNothing);
      expect(result, isNull);
    });
  });
}
