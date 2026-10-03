import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/database.dart';
import '../../data/services/app_pdf_file_store.dart';
import '../../data/services/file_picker_pdf_picker.dart';
import '../../domain/models/pdf_library_item.dart';
import '../../domain/services/pdf_file_store.dart';
import '../../domain/services/pdf_picker.dart';

final pdfPickerProvider = Provider<PdfPicker>((ref) => FilePickerPdfPicker());

final pdfFileStoreProvider = Provider<PdfFileStore>((ref) => AppPdfFileStore());

final pdfLibraryProvider =
    AsyncNotifierProvider<PdfLibraryController, List<PdfLibraryItem>>(
      PdfLibraryController.new,
    );

/// The PDF library: imported documents with their last read page,
/// persisted as JSON in [AppDatabase], newest first.
class PdfLibraryController extends AsyncNotifier<List<PdfLibraryItem>> {
  static const String storageKey = 'pdf_library';

  AppDatabase? _db;
  Future<void> _queue = Future<void>.value();
  DateTime? _lastAddedAt;

  @override
  Future<List<PdfLibraryItem>> build() async {
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

      final entries = <PdfLibraryItem>[];

      for (final item in decoded) {
        if (item is! Map<String, dynamic>) {
          continue;
        }

        try {
          final entry = PdfLibraryItem.fromJson(item);
          if (entry.path.isNotEmpty && entry.title.isNotEmpty) {
            entries.add(entry);
          }
        } catch (_) {
          // One damaged entry must not hide the rest of the
          // library: skip it and keep everything else.
        }
      }

      entries.sort((a, b) => b.addedAt.compareTo(a.addedAt));
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

  /// Copies the picked file into storage and records it.
  /// Rethrows when the copy fails so the caller can report it.
  Future<PdfLibraryItem> add({
    required String sourcePath,
    required String fileName,
  }) {
    return _enqueue(() async {
      final current = await _loaded();
      final storedPath = await ref
          .read(pdfFileStoreProvider)
          .retain(sourcePath, fileName);

      final item = PdfLibraryItem(
        path: storedPath,
        title: PdfLibraryItem.titleFromFileName(fileName),
        addedAt: _nextAddedAt(),
      );

      final next = [item, ...current]
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
      await _save(next);
      return item;
    });
  }

  /// Remembers where the reader stopped, plus the page count once
  /// the document has been opened.
  Future<void> savePosition(
    String path, {
    required int page,
    int pageCount = 0,
  }) {
    return _enqueue(() async {
      final current = await _loaded();
      final index = current.indexWhere((entry) => entry.path == path);
      if (index == -1) {
        return;
      }

      final existing = current[index];
      final knownPages = pageCount > 0 ? pageCount : existing.pageCount;

      if (existing.lastPage == page && existing.pageCount == knownPages) {
        return;
      }

      final next = [...current];
      next[index] = existing.copyWith(
        lastPage: page < 1 ? 1 : page,
        pageCount: knownPages,
      );
      await _save(next);
    });
  }

  /// Removes the entry and deletes its stored file.
  Future<void> remove(String path) {
    return _enqueue(() async {
      final current = await _loaded();
      final existing = current.where((entry) => entry.path == path).toList();

      await _save(current.where((entry) => entry.path != path).toList());

      for (final entry in existing) {
        try {
          await ref.read(pdfFileStoreProvider).remove(entry.path);
        } catch (_) {
          // Best effort: keep the entry removed either way.
        }
      }
    });
  }

  /// Timestamps are strictly increasing so rapid imports keep a
  /// stable newest-first order.
  DateTime _nextAddedAt() {
    final now = DateTime.now();
    final last = _lastAddedAt;

    if (last != null && !now.isAfter(last)) {
      return last.add(const Duration(milliseconds: 1));
    }

    _lastAddedAt = now;
    return now;
  }

  /// Serializes mutations so quick successions of imports do not
  /// overwrite each other.
  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();

    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }

  Future<List<PdfLibraryItem>> _loaded() async {
    try {
      return await future;
    } catch (_) {
      return state.valueOrNull ?? const [];
    }
  }

  Future<void> _save(List<PdfLibraryItem> entries) async {
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
