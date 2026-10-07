enum ChapterStatus {
  unknown,
  fetching,
  extracted,
  translating,
  ready,
  reading,
  completed,
  failed,
}

class Chapter {
  const Chapter({
    required this.id,
    required this.url,
    required this.title,
    required this.paragraphs,
    this.chapterNumber,
    this.previousChapterUrl,
    this.nextChapterUrl,
    this.imageUrls = const [],
    this.offlineImagePaths,
    this.status = ChapterStatus.unknown,
  });

  final String id;
  final String url;
  final String title;
  final List<String> paragraphs;
  final int? chapterNumber;
  final String? previousChapterUrl;
  final String? nextChapterUrl;

  /// Picture URLs for image chapters (manhwa), in reading order.
  final List<String> imageUrls;

  /// Local copies of [imageUrls], aligned by index; `null` entries
  /// are still only available over the network.
  final List<String?>? offlineImagePaths;
  final ChapterStatus status;

  /// Whether the chapter renders as pictures instead of text.
  bool get hasImages => imageUrls.isNotEmpty;

  Chapter copyWith({
    String? id,
    String? url,
    String? title,
    List<String>? paragraphs,
    int? chapterNumber,
    String? previousChapterUrl,
    String? nextChapterUrl,
    List<String>? imageUrls,
    List<String?>? offlineImagePaths,
    ChapterStatus? status,
  }) {
    return Chapter(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      paragraphs: paragraphs ?? this.paragraphs,
      chapterNumber: chapterNumber ?? this.chapterNumber,
      previousChapterUrl:
          previousChapterUrl ?? this.previousChapterUrl,
      nextChapterUrl: nextChapterUrl ?? this.nextChapterUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      offlineImagePaths: offlineImagePaths ?? this.offlineImagePaths,
      status: status ?? this.status,
    );
  }
}
