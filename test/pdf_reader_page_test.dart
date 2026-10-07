import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/library/domain/models/pdf_document.dart';
import 'package:novel_reader/features/library/domain/models/pdf_library_item.dart';
import 'package:novel_reader/features/library/domain/services/pdf_document_loader.dart';
import 'package:novel_reader/features/library/presentation/pages/pdf_reader_page.dart';
import 'package:novel_reader/features/library/presentation/providers/pdf_library_provider.dart';
import 'package:novel_reader/features/library/presentation/providers/pdf_reader_provider.dart';
import 'package:novel_reader/features/reader/domain/services/text_to_speech.dart';
import 'package:novel_reader/features/reader/presentation/providers/reader_tts_controller.dart';

class _FakeLoader implements PdfDocumentLoader {
  _FakeLoader({this.failOpen});

  final String? failOpen;
  final List<String> loadedChapters = [];

  @override
  Future<PdfDocumentInfo> open(String path) async {
    final failure = failOpen;
    if (failure != null) {
      throw Exception(failure);
    }

    return const PdfDocumentInfo(
      pageCount: 4,
      chapters: [
        PdfChapter(title: 'Chapter 1', startPage: 0, endPage: 2),
        PdfChapter(title: 'Chapter 2', startPage: 2, endPage: 4),
      ],
    );
  }

  @override
  Future<List<String>> loadParagraphs(String path, PdfChapter chapter) async {
    loadedChapters.add(chapter.title);

    return chapter.title == 'Chapter 1'
        ? const ['One a.', 'One b.']
        : const ['Two a.'];
  }

  @override
  void close() {}
}

class _FakeTts implements TextToSpeech {
  final List<String> spoken = [];

  /// Completion handler registered by the TTS controller, invoked by
  /// tests to simulate a paragraph finishing.
  void Function()? completion;

  @override
  Future<void> setLanguage(String language) async {}

  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  Future<void> setVoice(String name, String locale) async {}

  @override
  Future<List<TtsVoice>> getVoices() async => const [];

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {}

  @override
  void onCompletion(void Function() handler) {
    completion = handler;
  }

  @override
  void onCancel(void Function() handler) {}

  @override
  void onError(void Function(dynamic message) handler) {}
}

class _RecordingPdfLibrary extends PdfLibraryController {
  final List<int> savedPages = [];

  @override
  Future<List<PdfLibraryItem>> build() async => const [];

  @override
  Future<void> savePosition(
    String path, {
    required int page,
    int pageCount = 0,
  }) {
    savedPages.add(page);
    return Future.value();
  }
}

void main() {
  late _FakeLoader loader;
  late _FakeTts tts;
  late _RecordingPdfLibrary library;

  setUp(() {
    loader = _FakeLoader();
    tts = _FakeTts();
    library = _RecordingPdfLibrary();
  });

  Widget buildReader({int initialPage = 1, String? failOpen}) {
    final pageLoader =
        failOpen == null ? loader : _FakeLoader(failOpen: failOpen);

    return ProviderScope(
      overrides: [
        pdfDocumentLoaderProvider.overrideWithValue(pageLoader),
        pdfLibraryProvider.overrideWith(() => library),
        readerTtsControllerProvider.overrideWith(
          (ref) => ReaderTtsController(tts: tts),
        ),
      ],
      child: MaterialApp(
        home: PdfReaderPage(
          path: '/store/doc.pdf',
          title: 'Doc',
          initialPage: initialPage,
        ),
      ),
    );
  }

  /// The loading line keeps animating, so settle the route with
  /// bounded pumps instead of [WidgetTester.pumpAndSettle].
  Future<void> loadDocument(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Finder bodyText(String text) {
    return find.descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.text(text),
    );
  }

  IconButton iconButton(WidgetTester tester, String tooltip) {
    return tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    );
  }

  testWidgets('shows the first chapter with the reader controls', (
    tester,
  ) async {
    await tester.pumpWidget(buildReader());
    await loadDocument(tester);

    expect(find.text('Doc'), findsOneWidget);
    expect(bodyText('Chapter 1'), findsOneWidget);
    expect(bodyText('One a.'), findsOneWidget);
    expect(bodyText('One b.'), findsOneWidget);
    expect(find.byTooltip('Chapters'), findsOneWidget);
    expect(find.byTooltip('Auto-scroll'), findsOneWidget);
    expect(find.byTooltip('Font size'), findsOneWidget);
    expect(find.byKey(const ValueKey('tracker-track')), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(library.savedPages, [1]);
  });

  testWidgets('the chapter list opens and switches chapter', (tester) async {
    await tester.pumpWidget(buildReader());
    await loadDocument(tester);

    await tester.tap(find.byTooltip('Chapters'));
    await tester.pumpAndSettle();

    expect(find.text('Chapters'), findsOneWidget);
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 3'), findsOneWidget);

    await tester.tap(find.text('Chapter 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(bodyText('Chapter 2'), findsOneWidget);
    expect(bodyText('Two a.'), findsOneWidget);
    expect(bodyText('One a.'), findsNothing);
    expect(loader.loadedChapters, ['Chapter 1', 'Chapter 2']);
    expect(library.savedPages, [1, 3]);
  });

  testWidgets('the chapter drawer order can be reversed', (tester) async {
    await tester.pumpWidget(buildReader());
    await loadDocument(tester);

    await tester.tap(find.byTooltip('Chapters'));
    await tester.pumpAndSettle();

    Finder inDrawer(String text) =>
        find.descendant(of: find.byType(Drawer), matching: find.text(text));

    // Document chapters start in reading order.
    expect(find.byTooltip('Sort descending'), findsOneWidget);
    expect(
      tester.getTopLeft(inDrawer('Chapter 1')).dy,
      lessThan(tester.getTopLeft(inDrawer('Chapter 2')).dy),
    );

    await tester.tap(find.byTooltip('Sort descending'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Sort ascending'), findsOneWidget);
    expect(
      tester.getTopLeft(inDrawer('Chapter 2')).dy,
      lessThan(tester.getTopLeft(inDrawer('Chapter 1')).dy),
    );
  });

  testWidgets('next and previous move between chapters', (tester) async {
    await tester.pumpWidget(buildReader());
    await loadDocument(tester);

    expect(iconButton(tester, 'Previous chapter').onPressed, isNull);
    expect(iconButton(tester, 'Next chapter').onPressed, isNotNull);

    await tester.tap(find.byTooltip('Next chapter'));
    await tester.pump();
    await tester.pump();

    expect(bodyText('Chapter 2'), findsOneWidget);
    expect(iconButton(tester, 'Next chapter').onPressed, isNull);
    expect(iconButton(tester, 'Previous chapter').onPressed, isNotNull);

    await tester.tap(find.byTooltip('Previous chapter'));
    await tester.pump();
    await tester.pump();

    expect(bodyText('Chapter 1'), findsOneWidget);
  });

  testWidgets('play narrates the visible chapter', (tester) async {
    await tester.pumpWidget(buildReader());
    await loadDocument(tester);

    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump();

    expect(tts.spoken, ['One a.']);
    expect(find.text('Pause'), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await tester.pump();

    expect(find.text('Resume'), findsOneWidget);
  });

  testWidgets('finishing a chapter continues narration in the next one', (
    tester,
  ) async {
    await tester.pumpWidget(buildReader());
    await loadDocument(tester);

    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(tts.spoken, ['One a.']);

    tts.completion!();
    await tester.pump();
    expect(tts.spoken, ['One a.', 'One b.']);

    tts.completion!();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(tts.spoken, ['One a.', 'One b.', 'Two a.']);
    expect(bodyText('Chapter 2'), findsOneWidget);
    expect(library.savedPages, [1, 3]);
  });

  testWidgets('a resume page past the first chapter opens it', (tester) async {
    await tester.pumpWidget(buildReader(initialPage: 3));
    await loadDocument(tester);

    expect(bodyText('Chapter 2'), findsOneWidget);
    expect(library.savedPages, [3]);
  });

  testWidgets('a failed open shows an error state', (tester) async {
    await tester.pumpWidget(buildReader(failOpen: 'Broken file'));
    await loadDocument(tester);

    expect(find.text('Could not open PDF'), findsOneWidget);
    expect(find.text('Broken file'), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(find.byTooltip('Chapters'), findsNothing);
  });
}
