class ExtractedChapter {
  const ExtractedChapter({
    required this.title,
    required this.paragraphs,
    required this.url,
    this.novelTitle,
    this.nextChapterUrl,
    this.previousChapterUrl,
    this.imageUrls = const [],
    this.offlineImagePaths,
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
      imageUrls: [
        for (final image in (map['imageUrls'] as List? ?? const []))
          if (image is String) image,
      ],
      offlineImagePaths:
          (map['offlineImagePaths'] as List?)
              ?.map((path) => path is String ? path : null)
              .toList(),
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

  /// Pictures that make up the chapter (manhwa/comics), in reading
  /// order. Empty for text chapters.
  final List<String> imageUrls;

  /// Local file paths for [imageUrls], aligned by index and `null`
  /// for images that are still only on the network. Filled in when
  /// the chapter is saved for offline reading.
  final List<String?>? offlineImagePaths;

  /// Whether the chapter reads as a strip of pictures rather than
  /// text.
  bool get hasImages => imageUrls.isNotEmpty;

  ExtractedChapter copyWith({
    String? title,
    List<String>? paragraphs,
    String? url,
    String? novelTitle,
    String? nextChapterUrl,
    String? previousChapterUrl,
    List<String>? imageUrls,
    List<String?>? offlineImagePaths,
  }) {
    return ExtractedChapter(
      title: title ?? this.title,
      paragraphs: paragraphs ?? this.paragraphs,
      url: url ?? this.url,
      novelTitle: novelTitle ?? this.novelTitle,
      nextChapterUrl: nextChapterUrl ?? this.nextChapterUrl,
      previousChapterUrl: previousChapterUrl ?? this.previousChapterUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      offlineImagePaths: offlineImagePaths ?? this.offlineImagePaths,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'paragraphs': paragraphs,
      'url': url,
      'novelTitle': novelTitle,
      'nextChapterUrl': nextChapterUrl,
      'previousChapterUrl': previousChapterUrl,
      if (imageUrls.isNotEmpty) 'imageUrls': imageUrls,
      if (offlineImagePaths != null) 'offlineImagePaths': offlineImagePaths,
    };
  }
}
