/// One readable slice of a PDF: a chapter spans
/// `[startPage, endPage)` (0-based, end exclusive).
class PdfChapter {
  const PdfChapter({
    required this.title,
    required this.startPage,
    required this.endPage,
  });

  /// Outline label, or an empty string when the chapter was guessed
  /// from heading text.
  final String title;

  /// First page of the chapter (0-based, inclusive).
  final int startPage;

  /// Page after the last one of the chapter (0-based, exclusive).
  final int endPage;

  /// Title to show in the UI; falls back to the page range for
  /// chapters with no usable label.
  String get displayTitle =>
      title.isNotEmpty ? title : 'Pages ${startPage + 1}–$endPage';

  bool contains(int pageIndex) => pageIndex >= startPage && pageIndex < endPage;
}

/// Structure of an opened PDF: how long it is and how it splits into
/// chapters.
class PdfDocumentInfo {
  const PdfDocumentInfo({required this.pageCount, required this.chapters});

  final int pageCount;

  /// Always non-empty: a document with no detected chapters gets a
  /// single chapter covering every page.
  final List<PdfChapter> chapters;
}
