import 'dart:isolate';

import '../../domain/models/pdf_document.dart';
import '../../domain/services/pdf_document_loader.dart';
import 'pdf_isolate_tasks.dart';

/// Reads a PDF through short-lived isolates: structure once per file,
/// then one chapter's text at a time. Nothing parsed is ever held on
/// the UI isolate, so a large document neither stalls frames nor piles
/// up in the app's heap while the reader is open.
class SyncfusionPdfDocumentLoader implements PdfDocumentLoader {
  final Map<String, List<String>> _paragraphCache = {};

  String? _path;
  PdfDocumentInfo? _info;

  /// Bumped whenever the open file changes so a task that is still
  /// running cannot file its result against the wrong document.
  var _generation = 0;

  @override
  Future<PdfDocumentInfo> open(String path) async {
    if (_path == path && _info != null) {
      return _info!;
    }

    final generation = ++_generation;
    _path = null;
    _info = null;
    _paragraphCache.clear();

    final info = await Isolate.run(() => openPdfDocument(path));

    if (generation == _generation) {
      _path = path;
      _info = info;
    }

    return info;
  }

  @override
  Future<List<String>> loadParagraphs(String path, PdfChapter chapter) async {
    if (path != _path || _info == null) {
      await open(path);
    }

    final key = '${chapter.startPage}:${chapter.endPage}';
    final cached = _paragraphCache[key];
    if (cached != null) {
      return cached;
    }

    final generation = _generation;
    final paragraphs = await Isolate.run(
      () => extractPdfChapter(path, chapter),
    );

    if (generation == _generation) {
      _paragraphCache[key] = paragraphs;
    }

    return paragraphs;
  }

  @override
  void close() {
    _generation++;
    _path = null;
    _info = null;
    _paragraphCache.clear();
  }
}
