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
    this.paragraphCount = 0,
    this.chapterProgress = const {},
  });

  factory ReadNovel.fromJson(Map<String, Object?> json) {
    return ReadNovel(
      key: json['key'] as String? ?? '',
      url: json['url'] as String? ?? '',
      novelTitle: json['novelTitle'] as String?,
      novelTitleEn: json['novelTitleEn'] as String?,
      chapterTitle:
          (json['chapterTitle'] as String?) ?? json['title'] as String? ?? '',
      chapterTitleEn: json['chapterTitleEn'] as String?,
      paragraphIndex: (json['paragraphIndex'] as num?)?.toInt() ?? 0,
      paragraphCount: (json['paragraphCount'] as num?)?.toInt() ?? 0,
      chapterProgress: _progressFrom(json['chapterProgress']),
      readAt: DateTime.fromMillisecondsSinceEpoch(json['readAt'] as int? ?? 0),
    );
  }

  /// Progress of every chapter ever opened, keyed by chapter URL:
  /// `[paragraphIndex, paragraphCount]`.
  static Map<String, List<int>> _progressFrom(Object? json) {
    if (json is! Map) {
      return const {};
    }

    final progress = <String, List<int>>{};

    for (final entry in json.entries) {
      final value = entry.value;

      if (entry.key is! String || value is! List || value.length < 2) {
        continue;
      }

      final index = value[0];
      final count = value[1];

      if (index is! num || count is! num) {
        continue;
      }

      progress[entry.key as String] = [index.toInt(), count.toInt()];
    }

    return progress;
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

  /// How many paragraphs [chapterTitle] holds, so lists can show
  /// how far into it the reader got. `0` when never recorded.
  final int paragraphCount;

  /// Position inside every chapter opened so far, keyed by URL —
  /// what marks a chapter as read in the chapter lists.
  final Map<String, List<int>> chapterProgress;
  final DateTime readAt;

  /// What the list shows as the entry's name, preferring English.
  String get title =>
      novelTitleEn ?? novelTitle ?? chapterTitleEn ?? chapterTitle;

  /// Chapter line shown in the list, preferring English.
  String get displayChapterTitle => chapterTitleEn ?? chapterTitle;

  /// Whether this entry belongs to a picture series, which the
  /// Manhwa page keeps on its shelf instead of the novels list.
  bool get isManhwa => key.startsWith('manhwa:');

  /// Whether [url] has been opened at least once.
  bool hasRead(String url) =>
      url == this.url || chapterProgress.containsKey(url);

  /// How far into [url] the reader got, from `0` to `1`, or `null`
  /// when that chapter's length was never recorded.
  double? readFraction(String url) {
    final progress = chapterProgress[url];

    final index =
        progress != null
            ? progress.first
            : (url == this.url ? paragraphIndex : null);

    if (index == null) {
      return null;
    }

    final count =
        progress != null
            ? (progress.length > 1 ? progress[1] : 0)
            : paragraphCount;

    if (count <= 0) {
      return null;
    }

    if (count == 1) {
      return 1.0;
    }

    final share = index / (count - 1);
    if (share < 0) return 0.0;
    if (share > 1) return 1.0;
    return share;
  }

  /// `45%` for a chapter read a little under halfway, `null` when
  /// the chapter's length is unknown.
  String? readPercent(String url) {
    final share = readFraction(url);
    if (share == null) return null;
    return '${(share * 100).round()}%';
  }

  static String keyForNovel(String url, String novelTitle) {
    final uri = Uri.tryParse(url);
    return 'novel:${uri?.host ?? ''}:$novelTitle';
  }

  static String keyFor(String url) {
    final uri = Uri.tryParse(url);

    if (uri == null) {
      return 'url:$url';
    }

    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);

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
      'paragraphCount': paragraphCount,
      'chapterProgress': {
        for (final entry in chapterProgress.entries) entry.key: entry.value,
      },
      'readAt': readAt.millisecondsSinceEpoch,
    };
  }
}
