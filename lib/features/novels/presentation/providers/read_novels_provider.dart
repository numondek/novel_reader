import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/database.dart';
import '../../../scraper/data/services/series_path.dart';
import '../../../scraper/domain/models/manhwa_series.dart';
import '../../../scraper/presentation/providers/manhwa_shelf_provider.dart';
import '../../../translation/domain/language_detector.dart';
import '../../../translation/presentation/providers/translation_providers.dart';
import '../../domain/models/read_novel.dart';

final readNovelsProvider =
    AsyncNotifierProvider<ReadNovelsController, List<ReadNovel>>(
      ReadNovelsController.new,
    );

/// The read history minus its manhwa: picture series live on the
/// Manhwa page's shelf, so the novels list and the prefetch picker
/// only offer text novels.
final novelHistoryProvider = Provider<AsyncValue<List<ReadNovel>>>((ref) {
  final history = ref.watch(readNovelsProvider);

  if (history.isLoading || history.hasError) {
    return history;
  }

  final shelf =
      ref.watch(manhwaSeriesProvider).valueOrNull ?? const <ManhwaSeries>[];

  final seriesKeys = <String>{for (final entry in shelf) entry.novelKey};
  final novels = <ReadNovel>[];

  for (final entry in history.value ?? const <ReadNovel>[]) {
    final seriesKey = seriesKeyOf(entry.url);

    if (entry.isManhwa ||
        (seriesKey != null && seriesKeys.contains(seriesKey))) {
      continue;
    }

    novels.add(entry);
  }

  return AsyncData(novels);
});

/// The shelf key the chapters of [url] share, or `null` when the
/// URL cannot be read. Used to recognise series that were recorded
/// before chapters were grouped by series.
String? seriesKeyOf(String url) {
  final uri = Uri.tryParse(url);

  if (uri == null || uri.host.isEmpty) {
    return null;
  }

  return manhwaNovelKey(uri);
}

/// The read-history entry behind [novelKey]: either stored under it
/// directly, or a series whose chapters were keyed before they were
/// grouped under that same [novelKey].
ReadNovel? readEntryFor(List<ReadNovel> entries, String novelKey) {
  for (final entry in entries) {
    if (entry.key == novelKey) {
      return entry;
    }
  }

  if (!novelKey.startsWith('manhwa:')) {
    return null;
  }

  for (final entry in entries) {
    if (_sameSeries(seriesKeyOf(entry.url), novelKey)) {
      return entry;
    }
  }

  return null;
}

/// Whether two shelf keys hold the same series: equal, or one chapter
/// directory sitting inside the other — the shelf key shrinks to the
/// part every chapter link on the opened page had in common, which
/// can be shorter than the directory of a single chapter.
bool _sameSeries(String? key, String novelKey) {
  if (key == null || key.isEmpty) {
    return false;
  }

  if (key == novelKey) {
    return true;
  }

  const prefix = 'manhwa:';
  if (!key.startsWith(prefix) || !novelKey.startsWith(prefix)) {
    return false;
  }

  final left = key.substring(prefix.length);
  final right = novelKey.substring(prefix.length);
  final leftSlash = left.indexOf('/');
  final rightSlash = right.indexOf('/');

  if (leftSlash < 0 || rightSlash < 0) {
    return false;
  }

  if (left.substring(0, leftSlash) != right.substring(0, rightSlash)) {
    return false;
  }

  final leftPath = left.substring(leftSlash);
  final rightPath = right.substring(rightSlash);

  return leftPath == rightPath ||
      leftPath.startsWith('$rightPath/') ||
      rightPath.startsWith('$leftPath/');
}

/// The read-novel history: recorded whenever a chapter is opened,
/// persisted as JSON in [AppDatabase], newest first.
class ReadNovelsController extends AsyncNotifier<List<ReadNovel>> {
  static const String storageKey = 'read_novels';

  AppDatabase? _db;
  Future<void> _queue = Future<void>.value();
  DateTime? _lastReadAt;

  @override
  Future<List<ReadNovel>> build() async {
    _db = await _openDatabase();

    final raw = _db?.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }

      final entries = <ReadNovel>[];

      for (final item in decoded) {
        if (item is! Map<String, dynamic>) {
          continue;
        }

        final entry = ReadNovel.fromJson(item);
        if (entry.url.isNotEmpty && entry.key.isNotEmpty) {
          entries.add(entry);
        }
      }

      entries.sort((a, b) => b.readAt.compareTo(a.readAt));
      return entries;
    } catch (_) {
      return const [];
    }
  }

  Future<AppDatabase?> _openDatabase() async {
    try {
      return await AppDatabase.open();
    } catch (_) {
      return null;
    }
  }

  /// The shelf entry for the series [seriesKey] points at, or `null`
  /// when that series is not on the Manhwa page's shelf.
  ManhwaSeries? _shelvedSeries(String? seriesKey) {
    if (seriesKey == null) {
      return null;
    }

    try {
      final shelf =
          ref.read(manhwaSeriesProvider).valueOrNull ?? const <ManhwaSeries>[];

      for (final entry in shelf) {
        if (_sameSeries(seriesKey, entry.novelKey)) {
          return entry;
        }
      }
    } catch (_) {
      // A shelf that cannot be read must not stop the record.
    }

    return null;
  }

  /// Records a chapter opening; upserts the novel's entry so each
  /// novel appears once, pointing at its latest chapter.
  ///
  /// [paragraphIndex] is the reader's position inside the chapter.
  /// When omitted, an existing position is kept if the same chapter
  /// is reopened (resume) and reset to 0 for a new chapter.
  ///
  /// [manhwaKey] groups a picture series under the same key its
  /// shelf card uses, folding in whatever that series recorded
  /// before chapters were grouped by series.
  Future<void> record(
    String url,
    String chapterTitle, {
    String? novelTitle,
    int? paragraphIndex,
    int paragraphCount = 0,
    String? manhwaKey,
  }) {
    return _enqueue(() async {
      var name = novelTitle?.trim();
      if (name != null && name.isEmpty) name = null;

      // A series the shelf already holds groups under the shelf's
      // key, so two manhwa from one host never share an entry: below
      // a shared /manga/ folder their URLs tell them apart only by
      // their last path segment, which the plain URL key ignores.
      final shelved =
          manhwaKey == null ? _shelvedSeries(seriesKeyOf(url)) : null;
      final scope = manhwaKey ?? shelved?.novelKey;

      final key =
          scope ??
          (name != null
              ? ReadNovel.keyForNovel(url, name)
              : ReadNovel.keyFor(url));

      final current = await _loaded();

      ReadNovel? existing;

      // Keys the same series was recorded under before it was
      // grouped under [key]; their progress folds into this entry.
      final folded = <String>{};

      for (final entry in current) {
        if (entry.key == key) {
          existing = entry;
          continue;
        }

        if (scope != null && _sameSeries(seriesKeyOf(entry.url), scope)) {
          folded.add(entry.key);
        }
      }

      // The title the series carried, when this chapter came in
      // without one — folding entries must not lose the name.
      ReadNovel? titled;

      if (scope != null) {
        for (final entry in current) {
          if (entry.key != key && !folded.contains(entry.key)) continue;
          if (entry.novelTitle != null) {
            titled = entry;
            break;
          }
        }

        name ??= titled?.novelTitle ?? shelved?.title;
      }

      final resumed = existing != null && existing.url == url;
      final position =
          paragraphIndex ?? (resumed ? existing.paragraphIndex : 0);

      final progress = <String, List<int>>{};

      for (final source in current) {
        if (source.key != key && !folded.contains(source.key)) {
          continue;
        }

        progress.addAll(source.chapterProgress);

        if (source.url.isNotEmpty) {
          progress.putIfAbsent(
            source.url,
            () => [source.paragraphIndex, source.paragraphCount],
          );
        }
      }

      final prior = progress[url];
      final count =
          paragraphCount > 0
              ? paragraphCount
              : (prior != null && prior.length > 1 && prior[1] > 0
                  ? prior[1]
                  : 0);

      progress[url] = [position < 0 ? 0 : position, count];

      var nameEn =
          existing?.novelTitleEn ??
          (titled != null && titled.novelTitle == name
              ? titled.novelTitleEn
              : null);
      var chapterEn =
          existing != null && existing.chapterTitle == chapterTitle
              ? existing.chapterTitleEn
              : null;

      // Only chapter opens attempt translation; scroll-position
      // reports reuse whatever was stored (or the original text).
      if (paragraphIndex == null) {
        final needName = name != null && nameEn == null && containsCjk(name);
        final needChapter = chapterEn == null && containsCjk(chapterTitle);

        if (needName || needChapter) {
          final inputs = <String>[
            if (needName) name,
            if (needChapter) chapterTitle,
          ];

          try {
            final translated = await ref
                .read(translationServiceProvider)
                .translateParagraphs(inputs, targetLanguage: 'en');

            var cursor = 0;

            if (needName) {
              final value = translated[cursor++].trim();
              if (value.isNotEmpty && value != name) {
                nameEn = value;
              }
            }

            if (needChapter) {
              final value = translated[cursor].trim();
              if (value.isNotEmpty && value != chapterTitle) {
                chapterEn = value;
              }
            }
          } catch (_) {
            // Best effort: keep the original text and retry on the
            // next time this chapter is opened.
          }
        }
      }

      final entry = ReadNovel(
        key: key,
        url: url,
        novelTitle: name,
        novelTitleEn: nameEn,
        chapterTitle: chapterTitle,
        chapterTitleEn: chapterEn,
        paragraphIndex: position < 0 ? 0 : position,
        paragraphCount: count,
        chapterProgress: progress,
        readAt: _nextReadAt(),
      );

      final merged = [
        entry,
        for (final other in current)
          if (other.key != key && !folded.contains(other.key)) other,
      ]..sort((a, b) => b.readAt.compareTo(a.readAt));

      await _save(merged);
    });
  }

  Future<void> remove(String key) {
    return _enqueue(() async {
      final current = await _loaded();
      await _save(current.where((entry) => entry.key != key).toList());
    });
  }

  /// Drops every entry of one series: the key it was recorded
  /// under, plus chapters keyed before they were grouped. Deleting
  /// a manhwa from its shelf must not leave progress behind under a
  /// key nothing shows any more.
  Future<void> removeSeries(String novelKey) {
    return _enqueue(() async {
      final current = await _loaded();

      await _save([
        for (final entry in current)
          if (entry.key != novelKey &&
              !_sameSeries(seriesKeyOf(entry.url), novelKey))
            entry,
      ]);
    });
  }

  /// Timestamps are strictly increasing so rapid chapter opens keep
  /// a stable newest-first order.
  DateTime _nextReadAt() {
    final now = DateTime.now();
    final last = _lastReadAt;

    if (last != null && !now.isAfter(last)) {
      return last.add(const Duration(milliseconds: 1));
    }

    _lastReadAt = now;
    return now;
  }

  /// Serializes mutations so quick successions of chapter opens do
  /// not overwrite each other.
  Future<void> _enqueue(Future<void> Function() action) {
    final next = _queue.then((_) => action()).catchError((_) {});
    _queue = next;
    return next;
  }

  Future<List<ReadNovel>> _loaded() async {
    try {
      return await future;
    } catch (_) {
      return state.valueOrNull ?? const [];
    }
  }

  Future<void> _save(List<ReadNovel> entries) async {
    try {
      state = AsyncData(entries);

      final db = _db;
      if (db == null) {
        return;
      }

      await db.setString(
        storageKey,
        jsonEncode([for (final entry in entries) entry.toJson()]),
      );
    } catch (_) {
      // Best effort: keep the in-memory list even if persisting
      // fails (e.g. storage unavailable in tests).
    }
  }
}
