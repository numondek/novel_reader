class ExtractedChapter {
  const ExtractedChapter({
    required this.title,
    required this.paragraphs,
    required this.url,
    this.novelTitle,
    this.nextChapterUrl,
    this.previousChapterUrl,
  });

  factory ExtractedChapter.fromJson(Object? json) {
    final map = json is Map ? json : const <String, Object?>{};

    return ExtractedChapter(
      title: map['title'] as String? ?? '',
      paragraphs: [
        for (final paragraph in (map['paragraphs'] as List? ?? const []))
          if (paragraph is String) paragraph,
      ],
      url: map['url'] as String? ?? '',
      novelTitle: map['novelTitle'] as String?,
      nextChapterUrl: map['nextChapterUrl'] as String?,
      previousChapterUrl: map['previousChapterUrl'] as String?,
    );
  }

  final String title;
  final List<String> paragraphs;
  final String url;

  /// Name of the novel itself, when the page exposes it — used to
  /// tell novels apart on the same site.
  final String? novelTitle;
  final String? nextChapterUrl;
  final String? previousChapterUrl;

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'paragraphs': paragraphs,
      'url': url,
      'novelTitle': novelTitle,
      'nextChapterUrl': nextChapterUrl,
      'previousChapterUrl': previousChapterUrl,
    };
  }
}
