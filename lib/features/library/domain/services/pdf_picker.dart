/// A file chosen by the user through the platform picker.
class PickedPdf {
  const PickedPdf({required this.path, required this.name});

  /// Original location; may sit in a cache the app cannot rely on
  /// later, so imports copy it into storage.
  final String path;

  /// File name including extension.
  final String name;
}

abstract class PdfPicker {
  /// Returns the picked file, or null when the user cancels.
  Future<PickedPdf?> pick();
}
