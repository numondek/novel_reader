/// A PDF imported into the library.
///
/// The stored file path doubles as the entry's identity: importing
/// the same source twice copies it to a fresh path, so the two
/// entries stay separate.
class PdfLibraryItem {
  const PdfLibraryItem({
    required this.path,
    required this.title,
    required this.addedAt,
    this.lastPage = 1,
    this.pageCount = 0,
  });

  factory PdfLibraryItem.fromJson(Map<String, Object?> json) {
    return PdfLibraryItem(
      path: json['path'] as String? ?? '',
      title: json['title'] as String? ?? '',
      addedAt: DateTime.fromMillisecondsSinceEpoch(
        json['addedAt'] as int? ?? 0,
      ),
      lastPage: (json['lastPage'] as num?)?.toInt() ?? 1,
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Path of the copied file inside app storage.
  final String path;

  /// Display name without the `.pdf` extension.
  final String title;

  final DateTime addedAt;

  /// Page the reader stopped at (1-based).
  final int lastPage;

  /// Total pages, once the document has been opened; 0 when unknown.
  final int pageCount;

  PdfLibraryItem copyWith({int? lastPage, int? pageCount}) {
    return PdfLibraryItem(
      path: path,
      title: title,
      addedAt: addedAt,
      lastPage: lastPage ?? this.lastPage,
      pageCount: pageCount ?? this.pageCount,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'path': path,
      'title': title,
      'addedAt': addedAt.millisecondsSinceEpoch,
      'lastPage': lastPage,
      'pageCount': pageCount,
    };
  }

  /// Display name for an imported file: extension removed.
  static String titleFromFileName(String fileName) {
    final name = fileName.trim();
    final lower = name.toLowerCase();

    if (lower.endsWith('.pdf')) {
      final stripped = name.substring(0, name.length - 4).trim();
      if (stripped.isNotEmpty) {
        return stripped;
      }
    }

    return name;
  }
}
