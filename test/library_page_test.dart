import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/app/router/app_router.dart';
import 'package:novel_reader/features/library/domain/models/pdf_document.dart';
import 'package:novel_reader/features/library/domain/models/pdf_library_item.dart';
import 'package:novel_reader/features/library/domain/services/pdf_document_loader.dart';
import 'package:novel_reader/features/library/domain/services/pdf_file_store.dart';
import 'package:novel_reader/features/library/domain/services/pdf_picker.dart';
import 'package:novel_reader/features/library/presentation/pages/library_page.dart';
import 'package:novel_reader/features/library/presentation/pages/pdf_reader_page.dart';
import 'package:novel_reader/features/library/presentation/providers/pdf_library_provider.dart';
import 'package:novel_reader/features/library/presentation/providers/pdf_reader_provider.dart';

class _FakePdfLoader implements PdfDocumentLoader {
  @override
  Future<PdfDocumentInfo> open(String path) async {
    return const PdfDocumentInfo(
      pageCount: 3,
      chapters: [
        PdfChapter(title: 'Chapter 1', startPage: 0, endPage: 1),
        PdfChapter(title: 'Chapter 2', startPage: 1, endPage: 3),
      ],
    );
  }

  @override
  Future<List<String>> loadParagraphs(String path, PdfChapter chapter) async {
    if (chapter.title == 'Chapter 2') {
      return const ['Second chapter text.'];
    }
    return const ['First page text.'];
  }

  @override
  void close() {}
}

class _SeededPdfLibrary extends PdfLibraryController {
  _SeededPdfLibrary(this.seed);

  final List<PdfLibraryItem> seed;

  @override
  Future<List<PdfLibraryItem>> build() async => seed;
}

class _FakePdfPicker implements PdfPicker {
  _FakePdfPicker({this.result});

  final PickedPdf? result;

  @override
  Future<PickedPdf?> pick() async => result;
}

class _FakePdfFileStore implements PdfFileStore {
  final retained = <String, String>{};
  final removed = <String>[];
  var _count = 0;

  @override
  Future<String> retain(String sourcePath, String fileName) async {
    final stored = '/store/${_count++}_$fileName';
    retained[sourcePath] = stored;
    return stored;
  }

  @override
  Future<void> remove(String path) async {
    removed.add(path);
  }
}

List<PdfLibraryItem> seedEntries() {
  return [
    PdfLibraryItem(
      path: '/p/one.pdf',
      title: 'One',
      addedAt: DateTime.now(),
      lastPage: 3,
      pageCount: 12,
    ),
    PdfLibraryItem(path: '/p/two.pdf', title: 'Two', addedAt: DateTime.now()),
  ];
}

void main() {
  late _FakePdfFileStore store;
  late AppRouter router;

  setUp(() {
    store = _FakePdfFileStore();
    router = AppRouter();
  });

  Widget buildApp({List<PdfLibraryItem> seed = const [], PdfPicker? picker}) {
    return ProviderScope(
      overrides: [
        pdfLibraryProvider.overrideWith(() => _SeededPdfLibrary(seed)),
        pdfFileStoreProvider.overrideWithValue(store),
        if (picker != null) pdfPickerProvider.overrideWithValue(picker),
        pdfDocumentLoaderProvider.overrideWithValue(_FakePdfLoader()),
      ],
      child: MaterialApp.router(routerConfig: router.config()),
    );
  }

  Future<void> openLibrary(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    router.push(const LibraryRoute());
    await tester.pumpAndSettle();

    expect(find.byType(LibraryPage), findsOneWidget);
  }

  testWidgets('lists imported PDFs with resume info', (tester) async {
    await tester.pumpWidget(buildApp(seed: seedEntries()));
    await openLibrary(tester);

    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
    expect(find.textContaining('Page 3 of 12'), findsOneWidget);
    expect(find.text('Just now'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('No PDFs yet'), findsNothing);
  });

  testWidgets('tapping an entry reopens the reader at the saved page', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(seed: seedEntries()));
    await openLibrary(tester);

    await tester.tap(find.text('One'));
    // Same bounded-pump pattern as the add flow: the reader keeps
    // an indeterminate loading line animated.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(PdfReaderPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PdfReaderPage),
        matching: find.text('Second chapter text.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('delete removes only the tapped entry', (tester) async {
    await tester.pumpWidget(buildApp(seed: seedEntries()));
    await openLibrary(tester);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();

    expect(find.text('One'), findsNothing);
    expect(find.text('Two'), findsOneWidget);
    expect(store.removed, ['/p/one.pdf']);
  });

  testWidgets('empty library offers the add action', (tester) async {
    await tester.pumpWidget(buildApp());
    await openLibrary(tester);

    expect(find.text('No PDFs yet'), findsOneWidget);
    expect(find.text('Add PDF'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('picking a PDF stores it and opens the reader', (tester) async {
    await tester.pumpWidget(
      buildApp(
        picker: _FakePdfPicker(
          result: const PickedPdf(
            path: '/cache/sky.pdf',
            name: 'Sky & Sea.pdf',
          ),
        ),
      ),
    );
    await openLibrary(tester);

    await tester.tap(find.text('Add PDF'));
    // The reader keeps an indeterminate loading line animated, so
    // settle the route transition with bounded pumps instead.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(store.retained.containsKey('/cache/sky.pdf'), isTrue);
    expect(find.byType(PdfReaderPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PdfReaderPage),
        matching: find.text('Sky & Sea'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('canceling the picker keeps the library empty', (tester) async {
    await tester.pumpWidget(buildApp(picker: _FakePdfPicker(result: null)));
    await openLibrary(tester);

    await tester.tap(find.text('Add PDF'));
    await tester.pumpAndSettle();

    expect(find.text('No PDFs yet'), findsOneWidget);
    expect(find.byType(PdfReaderPage), findsNothing);
    expect(store.retained, isEmpty);
  });

  testWidgets('the order button reverses the list', (tester) async {
    await tester.pumpWidget(buildApp(seed: seedEntries()));
    await openLibrary(tester);

    // The library is stored newest-first, so the button offers the
    // ascending order.
    expect(find.byTooltip('Sort ascending'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('One')).dy,
      lessThan(tester.getTopLeft(find.text('Two')).dy),
    );

    await tester.tap(find.byTooltip('Sort ascending'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Sort descending'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Two')).dy,
      lessThan(tester.getTopLeft(find.text('One')).dy),
    );
  });
}
