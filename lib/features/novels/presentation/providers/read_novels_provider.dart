import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/database.dart';
import '../../../translation/domain/language_detector.dart';
import '../../../translation/presentation/providers/translation_providers.dart';
import '../../domain/models/read_novel.dart';

final readNovelsProvider =
    AsyncNotifierProvider<ReadNovelsController, List<ReadNovel>>(
  ReadNovelsController.new,
);

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

  /// Records a chapter opening; upserts the novel's entry so each
  /// novel appears once, pointing at its latest chapter.
  ///
  /// [paragraphIndex] is the reader's position inside the chapter.
  /// When omitted, an existing position is kept if the same chapter
  /// is reopened (resume) and reset to 0 for a new chapter.
  Future<void> record(
    String url,
    String chapterTitle, {
    String? novelTitle,
    int? paragraphIndex,
  }) {
    return _enqueue(() async {
      final trimmed = novelTitle?.trim();
      final name =
          trimmed == null || trimmed.isEmpty ? null : trimmed;

      final key = name != null
          ? ReadNovel.keyForNovel(url, name)
          : ReadNovel.keyFor(url);

      final current = await _loaded();

      ReadNovel? existing;
      for (final entry in current) {
        if (entry.key == key) {
          existing = entry;
          break;
        }
      }

      final resumed =
          existing != null && existing.url == url;
      final position = paragraphIndex ??
          (resumed ? existing.paragraphIndex : 0);

      var nameEn = existing?.novelTitleEn;
      var chapterEn = existing != null &&
              existing.chapterTitle == chapterTitle
          ? existing.chapterTitleEn
          : null;

      // Only chapter opens attempt translation; scroll-position
      // reports reuse whatever was stored (or the original text).
      if (paragraphIndex == null) {
        final needName = name != null &&
            nameEn == null &&
            containsCjk(name);
        final needChapter =
            chapterEn == null && containsCjk(chapterTitle);

        if (needName || needChapter) {
          final inputs = <String>[
            if (needName) name,
            if (needChapter) chapterTitle,
          ];

          try {
            final translated = await ref
                .read(translationServiceProvider)
                .translateParagraphs(
                  inputs,
                  targetLanguage: 'en',
                );

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
        readAt: _nextReadAt(),
      );

      final merged = [
        entry,
        ...current.where((other) => other.key != key),
      ]..sort((a, b) => b.readAt.compareTo(a.readAt));

      await _save(merged);
    });
  }

  Future<void> remove(String key) {
    return _enqueue(() async {
      final current = await _loaded();
      await _save(
        current.where((entry) => entry.key != key).toList(),
      );
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
        jsonEncode([
          for (final entry in entries) entry.toJson(),
        ]),
      );
    } catch (_) {
      // Best effort: keep the in-memory list even if persisting
      // fails (e.g. storage unavailable in tests).
    }
  }
}
