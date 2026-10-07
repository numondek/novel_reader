import '../models/extracted_chapter.dart';

/// Chapters kept on the device so a novel stays readable without a
/// network connection.
///
/// The scraper serves saved copies through [find]; the prefetch
/// feature fills the store through [save] and reports progress from
/// [load].
abstract class OfflineChapterStore {
  /// Everything saved for [novelKey], in reading order.
  Future<List<ExtractedChapter>> load(String novelKey);

  /// How many chapters are saved for [novelKey], without loading
  /// their text.
  Future<int> count(String novelKey);

  /// Saves [chapter] as the next chapter of [novelKey].
  Future<void> save(String novelKey, ExtractedChapter chapter);

  /// Forgets everything saved for [novelKey]: the chapters go back
  /// to needing a connection, so deleting a novel frees what it took
  /// to keep them.
  Future<void> remove(String novelKey);

  /// The saved copy of [url], or `null` when it was never saved.
  Future<ExtractedChapter?> find(String url);
}
