class ExtractedChapter {
  const ExtractedChapter({
    required this.title,
    required this.paragraphs,
    required this.url,
    this.novelTitle,
    this.nextChapterUrl,
    this.previousChapterUrl,
  });

  final String title;
  final List<String> paragraphs;
  final String url;

  /// Name of the novel itself, when the page exposes it — used to
  /// tell novels apart on the same site.
  final String? novelTitle;
  final String? nextChapterUrl;
  final String? previousChapterUrl;
}
