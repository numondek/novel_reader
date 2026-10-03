import 'package:file_picker/file_picker.dart';

import '../../domain/services/pdf_picker.dart';

/// Platform file picker restricted to PDF files.
class FilePickerPdfPicker implements PdfPicker {
  @override
  Future<PickedPdf?> pick() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.first;
    final path = file.path;
    if (path == null || path.isEmpty) {
      return null;
    }

    return PickedPdf(path: path, name: file.name);
  }
}
