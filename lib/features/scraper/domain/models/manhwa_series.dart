/// A manhwa the scraper opened, kept so the Manhwa page can show it
/// on a shelf instead of asking for its URL again.
class ManhwaSeries {
  const ManhwaSeries({
    required this.novelKey,
    required this.title,
    required this.sourceUrl,
    required this.openedAt,
    this.coverUrl,
    this.coverPath,
    this.extraUrls = const [],
  });

  factory ManhwaSeries.fromJson(Object? json) {
    final map = json is Map ? json : const <String, Object?>{};

    return ManhwaSeries(
      novelKey: map['novelKey'] as String? ?? '',
      title: map['title'] as String? ?? '',
      sourceUrl: map['sourceUrl'] as String? ?? '',
      coverUrl: map['coverUrl'] as String?,
      coverPath: map['coverPath'] as String?,
      extraUrls:
          (map['extraUrls'] as List?)?.whereType<String>().toList() ?? const [],
      openedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['openedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Groups this series' chapters in the offline store.
  final String novelKey;
  final String title;

  /// The page the series was opened from — its table of contents.
  final String sourceUrl;

  final String? coverUrl;

  /// Local copy of [coverUrl], when the cover could be downloaded.
  final String? coverPath;

  /// Other contents pages of the same series: opening the series
  /// merges their chapters into the list, so a series split over
  /// two pages (or mirrored elsewhere) still reads as one.
  final List<String> extraUrls;

  final DateTime openedAt;

  ManhwaSeries copyWith({String? coverPath, List<String>? extraUrls}) {
    return ManhwaSeries(
      novelKey: novelKey,
      title: title,
      sourceUrl: sourceUrl,
      coverUrl: coverUrl,
      coverPath: coverPath ?? this.coverPath,
      extraUrls: extraUrls ?? this.extraUrls,
      openedAt: openedAt,
    );
  }

  bool get hasCover => coverPath != null && coverPath!.isNotEmpty;

  Map<String, Object?> toJson() {
    return {
      'novelKey': novelKey,
      'title': title,
      'sourceUrl': sourceUrl,
      if (coverUrl != null) 'coverUrl': coverUrl,
      if (coverPath != null) 'coverPath': coverPath,
      'extraUrls': extraUrls,
      'openedAt': openedAt.millisecondsSinceEpoch,
    };
  }
}
