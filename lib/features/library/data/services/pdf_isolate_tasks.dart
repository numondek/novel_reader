import 'dart:io';
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../domain/models/pdf_document.dart';

/// Reads [path], finds its chapters and disposes everything before
/// returning. Run this with `Isolate.run`: a large file then costs the
/// UI isolate nothing, and a parse that runs out of memory fails
/// inside the worker instead of taking the app down.
PdfDocumentInfo openPdfDocument(String path) {
  final document = PdfDocument(inputBytes: _read(path));

  try {
    final pageCount = document.pages.count;

    if (pageCount < 1) {
      throw Exception('Document has no pages');
    }

    return PdfDocumentInfo(
      pageCount: pageCount,
      chapters: _detectChapters(document, pageCount),
    );
  } finally {
    document.dispose();
  }
}

/// Extracts one chapter's paragraphs, again for the calling isolate
/// only: the parsed document lives just long enough to copy the text
/// out of it.
List<String> extractPdfChapter(String path, PdfChapter chapter) {
  final document = PdfDocument(inputBytes: _read(path));

  try {
    final lastPage = document.pages.count - 1;
    // Chapter ends are exclusive; the extractor wants the last page
    // to include.
    final start = chapter.startPage.clamp(0, lastPage);
    final end = (chapter.endPage - 1).clamp(start, lastPage);

    final lines = PdfTextExtractor(
      document,
    ).extractTextLines(startPageIndex: start, endPageIndex: end);

    return _toParagraphs(lines);
  } finally {
    document.dispose();
  }
}

Uint8List _read(String path) {
  final bytes = File(path).readAsBytesSync();

  if (bytes.isEmpty) {
    throw Exception('File is empty');
  }

  return bytes;
}

List<PdfChapter> _detectChapters(PdfDocument document, int pageCount) {
  final outlined = _outlineChapters(document);
  if (outlined.length >= 2) {
    return _toChapters(outlined, pageCount);
  }

  final headings = _headingChapters(document, pageCount);
  if (headings.length >= 2) {
    return _toChapters(headings, pageCount);
  }

  final label = outlined.isEmpty ? '' : outlined.single.title;
  return [PdfChapter(title: label, startPage: 0, endPage: pageCount)];
}

/// Outline entries of the document, preferring the top level and
/// falling back to the whole tree when that is too sparse.
List<_Heading> _outlineChapters(PdfDocument document) {
  final top = _collectOutline(document, document.bookmarks, deep: false);
  if (top.length >= 2) {
    return top;
  }

  final deep = _collectOutline(document, document.bookmarks, deep: true);
  return deep.length >= 2 ? deep : top;
}

List<_Heading> _collectOutline(
  PdfDocument document,
  PdfBookmarkBase base, {
  required bool deep,
}) {
  final headings = <_Heading>[];

  for (var index = 0; index < base.count; index++) {
    final bookmark = base[index];
    final page = _pageIndex(document, bookmark);

    if (page >= 0) {
      headings.add(_Heading(bookmark.title.trim(), page));
    }

    if (deep) {
      headings.addAll(_collectOutline(document, bookmark, deep: true));
    }
  }

  return headings;
}

int _pageIndex(PdfDocument document, PdfBookmark bookmark) {
  try {
    final destination = bookmark.destination;
    if (destination == null) {
      return -1;
    }

    final index = document.pages.indexOf(destination.page);
    return index < 0 ? -1 : index;
  } catch (_) {
    return -1;
  }
}

/// Scans every page for chapter titles when the file has no usable
/// outline. Runs off the UI isolate, so the scan can take as long as
/// it likes without dropping frames.
List<_Heading> _headingChapters(PdfDocument document, int pageCount) {
  final headings = <_Heading>[];
  final extractor = PdfTextExtractor(document);

  for (var page = 0; page < pageCount; page++) {
    final lines = extractor.extractTextLines(
      startPageIndex: page,
      endPageIndex: page,
    );

    final bodySize = _dominantFontSize(lines);

    for (final line in lines) {
      final text = _clean(line.text);
      if (text.isEmpty || _isPageNumber(text)) {
        continue;
      }

      if (_looksLikeHeading(text, line.fontSize, bodySize)) {
        headings.add(_Heading(text, page));
        // One chapter per page: the title sits at its top.
        break;
      }
    }
  }

  return headings;
}

List<PdfChapter> _toChapters(List<_Heading> headings, int pageCount) {
  final kept = <_Heading>[];
  final seenPages = <int>{};

  for (final heading in headings) {
    if (heading.page < 0 || heading.page >= pageCount) {
      continue;
    }

    if (!seenPages.add(heading.page)) {
      continue;
    }

    kept.add(heading);
  }

  if (kept.isEmpty) {
    return [PdfChapter(title: '', startPage: 0, endPage: pageCount)];
  }

  final chapters = <PdfChapter>[];

  if (kept.first.page > 0) {
    chapters.add(PdfChapter(title: '', startPage: 0, endPage: kept.first.page));
  }

  for (var index = 0; index < kept.length; index++) {
    final start = kept[index].page;
    final end = index + 1 < kept.length ? kept[index + 1].page : pageCount;

    if (end <= start) {
      continue;
    }

    chapters.add(
      PdfChapter(title: kept[index].title, startPage: start, endPage: end),
    );
  }

  if (chapters.isEmpty) {
    return [PdfChapter(title: '', startPage: 0, endPage: pageCount)];
  }

  return chapters;
}

List<String> _toParagraphs(List<TextLine> lines) {
  final bodySize = _dominantFontSize(lines);
  final baseLeft = _baseLeft(lines);

  final paragraphs = <String>[];
  final buffer = StringBuffer();

  var previousText = '';
  var previousPage = -1;
  var previousTop = 0.0;
  var previousSize = bodySize;

  for (final line in lines) {
    final text = _clean(line.text);
    if (text.isEmpty || _isPageNumber(text)) {
      continue;
    }

    final heading = _looksLikeHeading(text, line.fontSize, bodySize);
    final newPage = line.pageIndex != previousPage;
    final startsParagraph = buffer.isEmpty;

    var breakBefore = false;

    if (!startsParagraph) {
      if (heading) {
        breakBefore = true;
      } else if (newPage) {
        // The vertical gap means nothing across pages; an indent
        // still marks a paragraph start, otherwise the sentence
        // simply continues onto this page.
        breakBefore = line.bounds.left > baseLeft + line.fontSize * 0.4;
      } else {
        // Distance between line tops; absolute value keeps the
        // check valid whichever way the page coordinates run.
        final pitch = (line.bounds.top - previousTop).abs();

        if (pitch > previousSize * 1.75) {
          breakBefore = true;
        } else if (line.bounds.left > baseLeft + line.fontSize * 0.4) {
          breakBefore = true;
        }
      }
    }

    if (!startsParagraph && breakBefore) {
      paragraphs.add(buffer.toString());
      buffer.clear();
    }

    if (buffer.isNotEmpty) {
      buffer.write(_separator(previousText, text));
    }

    buffer.write(text);

    previousText = text;
    previousPage = line.pageIndex;
    previousTop = line.bounds.top;
    previousSize = line.fontSize;

    if (heading && buffer.isNotEmpty) {
      paragraphs.add(buffer.toString());
      buffer.clear();
      previousText = '';
    }
  }

  if (buffer.isNotEmpty) {
    paragraphs.add(buffer.toString());
  }

  return paragraphs;
}

/// Most common size in the chapter, treated as the body size the
/// layout rules are measured against.
double _dominantFontSize(List<TextLine> lines) {
  final counts = <double, int>{};

  for (final line in lines) {
    if (line.text.trim().isEmpty) {
      continue;
    }

    counts[line.fontSize] = (counts[line.fontSize] ?? 0) + 1;
  }

  if (counts.isEmpty) {
    return 12;
  }

  var best = counts.keys.first;
  var bestCount = 0;

  counts.forEach((size, count) {
    if (count > bestCount || (count == bestCount && size < best)) {
      best = size;
      bestCount = count;
    }
  });

  return best;
}

/// Leftmost text edge in the chapter: indents are measured from it.
double _baseLeft(List<TextLine> lines) {
  var base = double.infinity;

  for (final line in lines) {
    if (line.text.trim().isEmpty) {
      continue;
    }

    if (line.bounds.left < base) {
      base = line.bounds.left;
    }
  }

  return base == double.infinity ? 0 : base;
}

String _separator(String previous, String next) {
  if (previous.isEmpty || next.isEmpty) {
    return '';
  }

  // CJK runs read without spaces; everything else joins with one.
  final needsSpace =
      !_isCjk(previous.codeUnits.last) || !_isCjk(next.codeUnits.first);

  return needsSpace ? ' ' : '';
}

bool _isCjk(int codeUnit) {
  return (codeUnit >= 0x3000 && codeUnit <= 0x303F) ||
      (codeUnit >= 0x3040 && codeUnit <= 0x30FF) ||
      (codeUnit >= 0x3400 && codeUnit <= 0x4DBF) ||
      (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
      (codeUnit >= 0xFF00 && codeUnit <= 0xFFEF);
}

String _clean(String text) {
  return text.replaceAll('\u0000', '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool _isPageNumber(String text) {
  return _pageNumber.hasMatch(text);
}

bool _looksLikeHeading(String text, double fontSize, double bodySize) {
  if (text.length > 60) {
    return false;
  }

  if (_structuralHeading.hasMatch(text) ||
      _sectionHeading.hasMatch(text) ||
      _numberedHeading.hasMatch(text) ||
      _cjkHeading.hasMatch(text)) {
    return true;
  }

  return fontSize > bodySize * 1.15 && text.length <= 40;
}

final RegExp _pageNumber = RegExp(
  r'^(?:page\s*)?-?\d{1,4}-?$',
  caseSensitive: false,
);

final RegExp _structuralHeading = RegExp(
  r'^(?:chapter|part|book|volume|section)\s+(?:\d{1,3}|[ivxlcdm]+)\b',
  caseSensitive: false,
);

final RegExp _sectionHeading = RegExp(
  r'^(?:prologue|epilogue|introduction|preface|foreword|afterword|'
  r'appendix|acknowledgments|glossary|interlude|author.s note|'
  r'bonus)\b',
  caseSensitive: false,
);

final RegExp _numberedHeading = RegExp(r'^\d{1,3}(?:[.、]\d{1,3})*[.、)]?\s+\S');

final RegExp _cjkHeading = RegExp(
  r'^(?:第\s*[0-9０-９一二三四五六七八九十百千零〇两]+\s*[章回节卷篇折集部]'
  r'|序章|序幕|楔子|尾声|尾聲|前言|引子|后记|後記|番外|外传|外傳'
  r'|终章|終章|结局|結局)',
);

class _Heading {
  const _Heading(this.title, this.page);

  final String title;
  final int page;
}
