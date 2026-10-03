import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/library/data/services/syncfusion_pdf_document_loader.dart';
import 'package:novel_reader/features/library/domain/models/pdf_document.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Document whose outline points at two chapters three pages apart.
Future<List<int>> outlinedDocument() async {
  final document = PdfDocument();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 12);

  final first = document.pages.add();
  first.graphics.drawString(
    'The first chapter body.',
    font,
    bounds: const Rect.fromLTWH(50, 60, 400, 20),
  );
  document.pages.add().graphics.drawString(
    'A page in between.',
    font,
    bounds: const Rect.fromLTWH(50, 60, 400, 20),
  );
  final last = document.pages.add();
  last.graphics.drawString(
    'The second chapter body.',
    font,
    bounds: const Rect.fromLTWH(50, 60, 400, 20),
  );

  document.bookmarks.add('Chapter 1').destination = PdfDestination(
    first,
    const Offset(50, 50),
  );
  document.bookmarks.add('Chapter 2').destination = PdfDestination(
    last,
    const Offset(50, 50),
  );

  final bytes = await document.save();
  document.dispose();
  return bytes;
}

/// Document with no outline but chapter titles drawn in a larger font.
Future<List<int>> headingDocument() async {
  final document = PdfDocument();
  final title = PdfStandardFont(PdfFontFamily.helvetica, 20);
  final body = PdfStandardFont(PdfFontFamily.helvetica, 12);

  final pageOne = document.pages.add();
  pageOne.graphics.drawString(
    'Chapter 1',
    title,
    bounds: const Rect.fromLTWH(50, 50, 400, 30),
  );
  pageOne.graphics.drawString(
    'Line A',
    body,
    bounds: const Rect.fromLTWH(50, 100, 400, 18),
  );
  pageOne.graphics.drawString(
    'Line B',
    body,
    bounds: const Rect.fromLTWH(50, 115, 400, 18),
  );
  pageOne.graphics.drawString(
    'Line C',
    body,
    bounds: const Rect.fromLTWH(50, 200, 400, 18),
  );

  final pageTwo = document.pages.add();
  pageTwo.graphics.drawString(
    'Chapter 2',
    title,
    bounds: const Rect.fromLTWH(50, 50, 400, 30),
  );
  pageTwo.graphics.drawString(
    'Page two text.',
    body,
    bounds: const Rect.fromLTWH(50, 100, 400, 18),
  );

  final bytes = await document.save();
  document.dispose();
  return bytes;
}

/// Document with no outline and nothing that looks like a heading.
Future<List<int>> plainDocument() async {
  final document = PdfDocument();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 12);

  for (var page = 0; page < 3; page++) {
    document.pages.add().graphics.drawString(
      'Plain body text line.',
      font,
      bounds: const Rect.fromLTWH(50, 60, 400, 20),
    );
  }

  final bytes = await document.save();
  document.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late SyncfusionPdfDocumentLoader loader;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pdf_loader_test');
    loader = SyncfusionPdfDocumentLoader();
  });

  tearDown(() {
    loader.close();
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  Future<String> write(String name, List<int> bytes) async {
    final file = File('${temp.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  test('reads chapters from the document outline', () async {
    final path = await write('outlined.pdf', await outlinedDocument());

    final info = await loader.open(path);

    expect(info.pageCount, 3);
    expect(info.chapters.map((chapter) => chapter.title), [
      'Chapter 1',
      'Chapter 2',
    ]);
    expect(info.chapters.first.startPage, 0);
    expect(info.chapters.last.startPage, 2);
    expect(info.chapters.first.endPage, 2);
    expect(info.chapters.last.endPage, 3);
  });

  test('extracts text for the requested chapter only', () async {
    final path = await write('outlined.pdf', await outlinedDocument());
    final info = await loader.open(path);

    final first = await loader.loadParagraphs(path, info.chapters.first);
    final last = await loader.loadParagraphs(path, info.chapters.last);

    // Chapter one owns every page up to where chapter two starts,
    // so the page in between belongs to it and carries on as one
    // paragraph; chapter two's text stays out.
    expect(first, ['The first chapter body. A page in between.']);
    expect(last, ['The second chapter body.']);
  });

  test('falls back to heading text when there is no outline', () async {
    final path = await write('headings.pdf', await headingDocument());

    final info = await loader.open(path);

    expect(info.pageCount, 2);
    expect(info.chapters.map((chapter) => chapter.title), [
      'Chapter 1',
      'Chapter 2',
    ]);
    expect(info.chapters.first.startPage, 0);
    expect(info.chapters.first.endPage, 1);
    expect(info.chapters.last.startPage, 1);
    expect(info.chapters.last.endPage, 2);

    final paragraphs = await loader.loadParagraphs(path, info.chapters.first);

    expect(paragraphs, ['Chapter 1', 'Line A Line B', 'Line C']);

    final second = await loader.loadParagraphs(path, info.chapters.last);

    expect(second, ['Chapter 2', 'Page two text.']);
  });

  test('a document with no chapters becomes a single chapter', () async {
    final path = await write('plain.pdf', await plainDocument());

    final info = await loader.open(path);

    expect(info.pageCount, 3);
    expect(info.chapters, hasLength(1));
    expect(info.chapters.single.startPage, 0);
    expect(info.chapters.single.endPage, 3);
    expect(info.chapters.single.displayTitle, 'Pages 1–3');

    final paragraphs = await loader.loadParagraphs(path, info.chapters.single);

    // Text carries on across page breaks, so the pages read as one
    // paragraph.
    expect(paragraphs, [
      'Plain body text line. Plain body text line. Plain body text line.',
    ]);
  });

  test('reopening another file replaces the open document', () async {
    final outlined = await write('outlined.pdf', await outlinedDocument());
    final plain = await write('plain.pdf', await plainDocument());

    final first = await loader.open(outlined);
    final second = await loader.open(plain);

    expect(first.pageCount, 3);
    expect(second.chapters, hasLength(1));

    // The first file is no longer open, so its text is re-read.
    final paragraphs = await loader.loadParagraphs(
      outlined,
      PdfChapter(title: 'Chapter 1', startPage: 0, endPage: 1),
    );

    expect(paragraphs, ['The first chapter body.']);
  });

  test('opening a missing file fails', () async {
    await expectLater(
      loader.open('${temp.path}${Platform.pathSeparator}missing.pdf'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('a failed open leaves the loader usable', () async {
    await expectLater(
      loader.open('${temp.path}${Platform.pathSeparator}missing.pdf'),
      throwsA(isA<FileSystemException>()),
    );

    final path = await write('outlined.pdf', await outlinedDocument());
    final info = await loader.open(path);

    expect(info.chapters, hasLength(2));
  });

  test('a superseded open cannot take over the newer file', () async {
    final outlined = await write('outlined.pdf', await outlinedDocument());
    final plain = await write('plain.pdf', await plainDocument());

    final older = loader.open(outlined);
    final newer = loader.open(plain);
    await Future.wait([older, newer]);

    // Whichever isolate finished last, the most recent call decides
    // which file the loader serves from now on.
    final paragraphs = await loader.loadParagraphs(
      plain,
      PdfChapter(title: '', startPage: 0, endPage: 1),
    );

    expect(paragraphs, ['Plain body text line.']);
  });
}
