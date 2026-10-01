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
    this.status = ChapterStatus.unknown,
  });

  final String id;
  final String url;
  final String title;
  final List<String> paragraphs;
  final int? chapterNumber;
  final String? previousChapterUrl;
  final String? nextChapterUrl;
  final ChapterStatus status;

  Chapter copyWith({
    String? id,
    String? url,
    String? title,
    List<String>? paragraphs,
    int? chapterNumber,
    String? previousChapterUrl,
    String? nextChapterUrl,
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
      status: status ?? this.status,
    );
  }
}
