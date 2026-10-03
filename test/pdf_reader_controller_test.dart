import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/library/domain/models/pdf_document.dart';
import 'package:novel_reader/features/library/domain/services/pdf_document_loader.dart';
import 'package:novel_reader/features/library/presentation/providers/pdf_reader_provider.dart';

PdfDocumentInfo sampleDocument() {
  return const PdfDocumentInfo(
    pageCount: 6,
    chapters: [
      PdfChapter(title: 'Chapter 1', startPage: 0, endPage: 2),
      PdfChapter(title: 'Chapter 2', startPage: 2, endPage: 4),
      PdfChapter(title: 'Chapter 3', startPage: 4, endPage: 6),
    ],
  );
}

class _FakeLoader implements PdfDocumentLoader {
  _FakeLoader({PdfDocumentInfo? info, this.failOpen})
    : info = info ?? sampleDocument();

  final PdfDocumentInfo? info;
  String? failOpen;
  String? failChapter;

  final List<String> openedPaths = [];
  final List<String> loadedChapters = [];
  final Map<String, Completer<List<String>>> pending = {};

  @override
  Future<PdfDocumentInfo> open(String path) async {
    openedPaths.add(path);

    final failure = failOpen;
    if (failure != null) {
      throw Exception(failure);
    }

    return info!;
  }

  @override
  Future<List<String>> loadParagraphs(String path, PdfChapter chapter) async {
    loadedChapters.add(chapter.title);

    final failure = failChapter;
    if (failure != null) {
      throw Exception(failure);
    }

    return ['Text of ${chapter.title}'];
  }

  @override
  void close() {}
}

class _SlowLoader extends _FakeLoader {
  _SlowLoader() : super();

  @override
  Future<List<String>> loadParagraphs(String path, PdfChapter chapter) {
    loadedChapters.add(chapter.title);

    final completer = Completer<List<String>>();
    pending[chapter.title] = completer;
    return completer.future;
  }
}

void main() {
  late List<int> savedPages;

  PdfReaderController makeController(PdfDocumentLoader loader) {
    return PdfReaderController(
      path: '/p/doc.pdf',
      loader: loader,
      onChapterOpen: (page, pageCount) {
        savedPages.add(page);
      },
    );
  }

  setUp(() {
    savedPages = [];
  });

  test('opens on the chapter that holds the saved page', () async {
    final loader = _FakeLoader();
    final controller = makeController(loader);

    await controller.open(3);

    expect(loader.openedPaths, ['/p/doc.pdf']);
    expect(controller.state.chapterIndex, 1);
    expect(controller.state.chapter?.title, 'Chapter 2');
    expect(controller.state.paragraphs, ['Text of Chapter 2']);
    expect(controller.state.isLoadingChapter, isFalse);
    expect(savedPages, [3]);
  });

  test('a page outside every chapter falls back to the first', () async {
    final controller = makeController(_FakeLoader());

    await controller.open(99);

    expect(controller.state.chapterIndex, 0);
    expect(savedPages, [1]);
  });

  test('a failed open reports the message', () async {
    final loader = _FakeLoader(failOpen: 'Broken file');
    final controller = makeController(loader);

    await controller.open(1);

    expect(controller.state.document, isNull);
    expect(controller.state.error, 'Broken file');
    expect(controller.state.isLoadingDocument, isFalse);
    expect(savedPages, isEmpty);
  });

  test('next and previous stay inside the document', () async {
    final loader = _FakeLoader();
    final controller = makeController(loader);

    await controller.open(1);
    expect(controller.state.chapterIndex, 0);
    expect(controller.state.hasPreviousChapter, isFalse);

    await controller.nextChapter();
    await controller.nextChapter();
    expect(controller.state.chapterIndex, 2);
    expect(controller.state.hasNextChapter, isFalse);

    await controller.nextChapter();
    expect(controller.state.chapterIndex, 2);

    await controller.previousChapter();
    expect(controller.state.chapterIndex, 1);
    expect(controller.state.paragraphs, ['Text of Chapter 2']);

    await controller.previousChapter();
    await controller.previousChapter();
    expect(controller.state.chapterIndex, 0);

    expect(loader.loadedChapters, [
      'Chapter 1',
      'Chapter 2',
      'Chapter 3',
      'Chapter 2',
      'Chapter 1',
    ]);
    expect(savedPages, [1, 3, 5, 3, 1]);
  });

  test('a failed chapter load clears the text and reports it', () async {
    final loader = _FakeLoader();
    final controller = makeController(loader);

    await controller.open(1);
    expect(controller.state.paragraphs, isNotEmpty);

    loader.failChapter = 'Page exploded';
    await controller.openChapter(1);

    expect(controller.state.chapterIndex, 1);
    expect(controller.state.paragraphs, isEmpty);
    expect(controller.state.error, 'Page exploded');
    expect(controller.state.isLoadingChapter, isFalse);
  });

  test('re-selecting the visible chapter does not reload it', () async {
    final loader = _FakeLoader();
    final controller = makeController(loader);

    await controller.open(1);
    await controller.openChapter(0);

    expect(loader.loadedChapters, ['Chapter 1']);
    expect(savedPages, [1]);
  });

  test('a slow chapter cannot overwrite a newer one', () async {
    final loader = _SlowLoader();
    final controller = makeController(loader);

    final opening = controller.open(1);
    await pumpEventQueue();
    expect(controller.state.chapterIndex, 0);
    expect(loader.pending.keys, ['Chapter 1']);

    final switching = controller.openChapter(1);
    await pumpEventQueue();
    expect(controller.state.chapterIndex, 1);
    expect(controller.state.isLoadingChapter, isTrue);

    loader.pending['Chapter 2']!.complete(['Fresh text']);
    await switching;

    expect(controller.state.paragraphs, ['Fresh text']);
    expect(controller.state.isLoadingChapter, isFalse);

    loader.pending['Chapter 1']!.complete(['Stale text']);
    await opening;

    expect(controller.state.chapterIndex, 1);
    expect(controller.state.paragraphs, ['Fresh text']);
  });

  test('setActiveParagraph tracks the paragraph being read', () async {
    final controller = makeController(_FakeLoader());

    await controller.open(1);

    controller.setActiveParagraph(2);

    expect(controller.state.activeParagraph, 2);

    await controller.nextChapter();

    expect(controller.state.activeParagraph, 0);
  });
}
