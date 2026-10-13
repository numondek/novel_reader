import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/database.dart';
import '../../../../core/utils/url_utils.dart';
import '../../../prefetch/presentation/providers/offline_chapter_store_provider.dart';
import '../../domain/models/manhwa_series.dart';

/// The manhwa the user has opened, newest first — the grid behind
/// the Manhwa page, persisted as JSON in [AppDatabase].
final manhwaSeriesProvider =
    AsyncNotifierProvider<ManhwaSeriesController, List<ManhwaSeries>>(
      ManhwaSeriesController.new,
    );

/// How many chapters each shelf entry has saved, keyed by
/// [ManhwaSeries.novelKey], so a card can say what is readable
/// without a connection.
final manhwaSavedCountsProvider = FutureProvider.autoDispose<Map<String, int>>((
  ref,
) async {
  final series =
      ref.watch(manhwaSeriesProvider).valueOrNull ?? const <ManhwaSeries>[];
  final store = ref.read(offlineChapterStoreProvider);

  final counts = <String, int>{};
  for (final entry in series) {
    counts[entry.novelKey] = await store.count(entry.novelKey);
  }

  return counts;
});

class ManhwaSeriesController extends AsyncNotifier<List<ManhwaSeries>> {
  static const String storageKey = 'manhwa_shelf';

  AppDatabase? _db;
  Future<void> _queue = Future<void>.value();
  DateTime? _lastOpenedAt;

  @override
  Future<List<ManhwaSeries>> build() async {
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

      final entries = <ManhwaSeries>[];

      for (final item in decoded) {
        if (item is! Map<String, dynamic>) {
          continue;
        }

        final entry = ManhwaSeries.fromJson(item);
        if (entry.novelKey.isNotEmpty && entry.sourceUrl.isNotEmpty) {
          entries.add(entry);
        }
      }

      entries.sort((a, b) => b.openedAt.compareTo(a.openedAt));
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

  /// Puts [series] on the shelf, replacing whatever it already held
  /// under the same key.
  Future<void> record(ManhwaSeries series) {
    return _enqueue(() async {
      if (series.novelKey.isEmpty || series.sourceUrl.isEmpty) {
        return;
      }

      final current = await _loaded();
      final openedAt = _nextOpenedAt();

      // Reopening must not drop the extra contents pages the shelf
      // kept for this series on an earlier opening.
      var extraUrls = series.extraUrls;

      if (extraUrls.isEmpty) {
        for (final other in current) {
          if (other.novelKey == series.novelKey) {
            extraUrls = other.extraUrls;
            break;
          }
        }
      }

      final entry = ManhwaSeries(
        novelKey: series.novelKey,
        title: series.title,
        sourceUrl: series.sourceUrl,
        coverUrl: series.coverUrl,
        coverPath: series.coverPath,
        extraUrls: extraUrls,
        openedAt: openedAt,
      );

      final merged = [
        entry,
        ...current.where((other) => other.novelKey != entry.novelKey),
      ]..sort((a, b) => b.openedAt.compareTo(a.openedAt));

      await _save(merged);
    });
  }

  Future<void> remove(String novelKey) {
    return _enqueue(() async {
      final current = await _loaded();
      await _save(
        current.where((entry) => entry.novelKey != novelKey).toList(),
      );
    });
  }

  /// Keeps another contents page on [novelKey]: opening the series
  /// merges that page's chapters into its list. An unreadable URL, a
  /// link the entry already carries, or a series no longer on the
  /// shelf changes nothing.
  Future<void> addContentsUrl(String novelKey, String rawUrl) {
    return _enqueue(() async {
      final url = normalizeUrl(rawUrl);
      if (url == null) {
        return;
      }

      final current = await _loaded();
      final updated = <ManhwaSeries>[];
      var found = false;

      for (final entry in current) {
        if (entry.novelKey != novelKey || entry.extraUrls.contains(url)) {
          updated.add(entry);
          continue;
        }

        found = true;
        updated.add(entry.copyWith(extraUrls: [...entry.extraUrls, url]));
      }

      if (found) {
        await _save(updated);
      }
    });
  }

  /// Timestamps are strictly increasing so a quick run through a
  /// few series keeps a stable newest-first order.
  DateTime _nextOpenedAt() {
    final now = DateTime.now();
    final last = _lastOpenedAt;

    if (last != null && !now.isAfter(last)) {
      return last.add(const Duration(milliseconds: 1));
    }

    _lastOpenedAt = now;
    return now;
  }

  /// Serializes mutations so two openings at once do not overwrite
  /// each other.
  Future<void> _enqueue(Future<void> Function() action) {
    final next = _queue.then((_) => action()).catchError((_) {});
    _queue = next;
    return next;
  }

  Future<List<ManhwaSeries>> _loaded() async {
    try {
      return await future;
    } catch (_) {
      return state.valueOrNull ?? const [];
    }
  }

  Future<void> _save(List<ManhwaSeries> entries) async {
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
      // Best effort: keep the in-memory shelf even if persisting
      // fails (e.g. storage unavailable in tests).
    }
  }
}
