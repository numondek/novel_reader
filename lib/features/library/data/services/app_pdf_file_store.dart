import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/services/pdf_file_store.dart';

/// Stores imported PDFs in `<documents>/pdfs`.
class AppPdfFileStore implements PdfFileStore {
  @override
  Future<String> retain(String sourcePath, String fileName) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}pdfs');
    await dir.create(recursive: true);

    final safe = _safeName(fileName);
    var target = '${dir.path}${Platform.pathSeparator}$safe';

    if (await File(target).exists()) {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      target = '${dir.path}${Platform.pathSeparator}${stamp}_$safe';
    }

    await File(sourcePath).copy(target);
    return target;
  }

  @override
  Future<void> remove(String path) async {
    try {
      final file = File(path);

      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best effort: a leftover file never breaks library updates.
    }
  }

  String _safeName(String fileName) {
    final name = fileName.trim().replaceAll(RegExp(r'[/\\]'), '_');
    return name.isEmpty ? 'document.pdf' : name;
  }
}
