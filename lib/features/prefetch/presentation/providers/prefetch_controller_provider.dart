import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../novels/domain/models/read_novel.dart';
import '../../../novels/presentation/providers/read_novels_provider.dart';
import '../../../scraper/data/repositories/scraper_repository.dart';
import '../../../scraper/domain/models/extracted_chapter.dart';
import '../../../scraper/domain/services/offline_chapter_store.dart';
import '../../../scraper/presentation/providers/scraper_providers.dart';
import 'offline_chapter_store_provider.dart';

/// Chapters fetched per batch: small enough to finish quickly, and
/// the next tap continues where the last one stopped.
const int prefetchBatchSize = 10;

/// Prefetch progress for one novel, keyed by [ReadNovel.key].
///
/// Kept alive while the page is open so the saved summary survives
/// unrelated rebuilds; the chapter being read is resolved when a
/// batch starts.
final prefetchControllerProvider =
    StateNotifierProvider.family<PrefetchController, PrefetchState, String>((
      ref,
      novelKey,
    ) {
      ReadNovel? presentChapter() {
        final novels =
            ref.read(readNovelsProvider).valueOrNull ?? const <ReadNovel>[];

        for (final novel in novels) {
          if (novel.key == novelKey) return novel;
        }

        return null;
      }

      return PrefetchController(
        novelKey: novelKey,
        seedOf: presentChapter,
        scraper: ref.read(scraperRepositoryProvider),
        store: ref.read(offlineChapterStoreProvider),
      );
    });

/// What the prefetch page shows for one novel.
class PrefetchState {
  const PrefetchState({
    this.savedCount = 0,
    this.savedTitles = const [],
    this.savedUrls = const [],
    this.isFetching = false,
    this.fetchedCount = 0,
    this.hasNextBatch = true,
    this.error,
    this.ready = false,
  });

  /// Chapters already stored on the device for this novel.
  final int savedCount;

  /// Titles of [savedCount], in the order they were saved.
  final List<String> savedTitles;

  /// URLs of [savedCount], aligned with [savedTitles], so the list
  /// can tell which of them have been read.
  final List<String> savedUrls;

  final bool isFetching;

  /// Chapters saved by the batch in progress, out of
  /// [prefetchBatchSize].
  final int fetchedCount;

  /// Whether another batch can be attempted; turns false once the
  /// chapter chain ends.
  final bool hasNextBatch;

  /// The last failure, shown until the next attempt starts.
  final String? error;

  /// Whether the saved summary finished loading.
  final bool ready;

  bool get hasSaved => savedCount > 0;

  String get buttonLabel =>
      hasSaved
          ? 'Get next $prefetchBatchSize chapters'
          : 'Save $prefetchBatchSize chapters';

  PrefetchState copyWith({
    int? savedCount,
    List<String>? savedTitles,
    List<String>? savedUrls,
    bool? isFetching,
    int? fetchedCount,
    bool? hasNextBatch,
    String? error,
    bool? ready,
    bool clearError = false,
  }) {
    return PrefetchState(
      savedCount: savedCount ?? this.savedCount,
      savedTitles: savedTitles ?? this.savedTitles,
      savedUrls: savedUrls ?? this.savedUrls,
      isFetching: isFetching ?? this.isFetching,
      fetchedCount: fetchedCount ?? this.fetchedCount,
      hasNextBatch: hasNextBatch ?? this.hasNextBatch,
      error: clearError ? null : (error ?? this.error),
      ready: ready ?? this.ready,
    );
  }
}

/// Saves batches of chapters from a novel's chain to local storage,
/// starting from the chapter the user is reading now.
class PrefetchController extends StateNotifier<PrefetchState> {
  PrefetchController({
    required this.novelKey,
    required ReadNovel? Function() seedOf,
    required this.scraper,
    required this.store,
  }) : _seedOf = seedOf,
       super(const PrefetchState()) {
    _restore();
  }

  final String novelKey;

  /// Resolves the chapter the user is reading right now, so saving
  /// follows the present reading position instead of a snapshot
  /// taken earlier.
  final ReadNovel? Function() _seedOf;
  final ScraperRepository scraper;
  final OfflineChapterStore store;

  List<ExtractedChapter> _saved = const [];

  /// Reloads what is already on the device so the page opens with an
  /// honest count and the next batch continues after it.
  Future<void> _restore() async {
    final saved = await store.load(novelKey);
    if (!mounted) return;

    _saved = saved;
    state = state.copyWith(
      ready: true,
      savedCount: saved.length,
      savedTitles: [for (final chapter in saved) chapter.title],
      savedUrls: [for (final chapter in saved) chapter.url],
      hasNextBatch: _hasNextBatch(),
      clearError: true,
    );
  }

  /// Saves up to [prefetchBatchSize] more chapters, starting at the
  /// chapter the user is reading now unless it is already saved —
  /// then right after the last saved one.
  Future<void> fetchNextBatch() async {
    if (!state.ready || state.isFetching || !state.hasNextBatch) {
      return;
    }

    final start = _nextStartUrl();
    if (start == null) {
      state = state.copyWith(error: 'No chapter to start from.');
      return;
    }

    state = state.copyWith(isFetching: true, fetchedCount: 0, clearError: true);

    var url = start;
    var fetched = 0;
    Object? failure;

    while (fetched < prefetchBatchSize) {
      if (!mounted) return;

      final kept = _findSaved(url);

      if (kept != null) {
        // Already offline: walk past it without downloading again.
        final next = kept.nextChapterUrl;
        if (next == null) break;
        url = next;
        continue;
      }

      try {
        final chapter = await scraper.extractChapter(url);
        if (!mounted) return;

        await store.save(novelKey, chapter);
        if (!mounted) return;

        _saved = [..._saved, chapter];
        fetched += 1;

        state = state.copyWith(
          savedCount: _saved.length,
          savedTitles: [...state.savedTitles, chapter.title],
          savedUrls: [...state.savedUrls, chapter.url],
          fetchedCount: fetched,
        );
      } catch (error) {
        failure = error;
        break;
      }

      final next = _saved.last.nextChapterUrl;
      if (next == null) break;
      url = next;
    }

    if (!mounted) return;

    state = state.copyWith(
      isFetching: false,
      hasNextBatch: _hasNextBatch(),
      error: failure == null ? null : _messageOf(failure),
    );
  }

  /// Where the next batch starts: the chapter being read now unless
  /// it is already saved, in which case right after the last saved
  /// chapter.
  String? _nextStartUrl() {
    final current = _seedOf()?.url ?? '';

    if (current.isEmpty) {
      return _saved.isEmpty ? null : _saved.last.nextChapterUrl;
    }

    if (_findSaved(current) == null) return current;

    return _saved.last.nextChapterUrl;
  }

  bool _hasNextBatch() {
    final current = _seedOf()?.url ?? '';

    if (current.isNotEmpty && _findSaved(current) == null) {
      return true;
    }

    if (_saved.isEmpty) {
      return state.hasNextBatch;
    }

    return _saved.last.nextChapterUrl != null;
  }

  ExtractedChapter? _findSaved(String url) {
    for (final chapter in _saved) {
      if (chapter.url == url) return chapter;
    }

    return null;
  }

  static final RegExp _errorPrefix = RegExp(
    r'^(?:[A-Za-z]*Exception|[A-Za-z]*Error):\s*',
  );

  String _messageOf(Object error) {
    final message = error.toString().trim().replaceFirst(_errorPrefix, '');

    return message.isEmpty ? 'Something went wrong' : message;
  }
}
