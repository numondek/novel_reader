import '../models/pdf_document.dart';

/// Opens PDF files and turns them into chapters plus text, so the
/// reader can load one chapter at a time instead of the whole file.
///
/// Kept behind an interface so widget tests can substitute a fake and
/// never touch the parsing stack.
abstract class PdfDocumentLoader {
  /// Reads [path] and works out its chapter structure.
  Future<PdfDocumentInfo> open(String path);

  /// Extracts the readable paragraphs of [chapter].
  Future<List<String>> loadParagraphs(String path, PdfChapter chapter);

  /// Releases the currently open document.
  void close();
}
