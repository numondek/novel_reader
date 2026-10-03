/// Copies imported PDFs into app storage and deletes them again.
abstract class PdfFileStore {
  /// Copies [sourcePath] under a unique name derived from [fileName]
  /// and returns the stored path.
  Future<String> retain(String sourcePath, String fileName);

  /// Deletes a stored file; missing files are ignored.
  Future<void> remove(String path);
}
