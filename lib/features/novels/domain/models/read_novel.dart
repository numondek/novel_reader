/// A novel the user has read, tracked by the most recently opened
/// chapter.
///
/// Entries are keyed by novel name (host + name) when the page
/// exposes one, so two novels from the same site stay separate even
/// when their URLs share a path prefix. Falls back to a URL-derived
/// key when no novel name is available.
class ReadNovel {
  const ReadNovel({
    required this.key,
    required this.url,
    required this.chapterTitle,
    required this.readAt,
    this.novelTitle,
    this.novelTitleEn,
    this.chapterTitleEn,
    this.paragraphIndex = 0,
  });

  factory ReadNovel.fromJson(Map<String, Object?> json) {
    return ReadNovel(
      key: json['key'] as String? ?? '',
      url: json['url'] as String? ?? '',
      novelTitle: json['novelTitle'] as String?,
      novelTitleEn: json['novelTitleEn'] as String?,
      chapterTitle: (json['chapterTitle'] as String?) ??
          json['title'] as String? ??
          '',
      chapterTitleEn: json['chapterTitleEn'] as String?,
      paragraphIndex:
          (json['paragraphIndex'] as num?)?.toInt() ?? 0,
      readAt: DateTime.fromMillisecondsSinceEpoch(
        json['readAt'] as int? ?? 0,
      ),
    );
  }

  final String key;
  final String url;

  /// Name of the novel itself, when known (original text).
  final String? novelTitle;

  /// English translation of [novelTitle], filled in when the
  /// original is CJK. Originals stay untouched so entry keys and
  /// identity remain stable.
  final String? novelTitleEn;

  /// Title of the chapter read most recently (original text).
  final String chapterTitle;

  /// English translation of [chapterTitle], when the original is
  /// CJK.
  final String? chapterTitleEn;

  /// Paragraph the reader stopped at inside [chapterTitle], so the
  /// app can resume where the user left off after a restart.
  final int paragraphIndex;
  final DateTime readAt;

  /// What the list shows as the entry's name, preferring English.
  String get title =>
      novelTitleEn ??
      novelTitle ??
      chapterTitleEn ??
      chapterTitle;

  /// Chapter line shown in the list, preferring English.
  String get displayChapterTitle =>
      chapterTitleEn ?? chapterTitle;

  static String keyForNovel(String url, String novelTitle) {
    final uri = Uri.tryParse(url);
    return 'novel:${uri?.host ?? ''}:$novelTitle';
  }

  static String keyFor(String url) {
    final uri = Uri.tryParse(url);

    if (uri == null) {
      return 'url:$url';
    }

    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty);

    if (segments.isEmpty) {
      return 'url:${uri.host}';
    }

    return 'url:${uri.host}:${segments.first}';
  }

  String get host {
    final uri = Uri.tryParse(url);

    if (uri == null || uri.host.isEmpty) {
      return url;
    }

    return uri.host;
  }

  Map<String, Object?> toJson() {
    return {
      'key': key,
      'url': url,
      'novelTitle': novelTitle,
      'novelTitleEn': novelTitleEn,
      'chapterTitle': chapterTitle,
      'chapterTitleEn': chapterTitleEn,
      'paragraphIndex': paragraphIndex,
      'readAt': readAt.millisecondsSinceEpoch,
    };
  }
}
