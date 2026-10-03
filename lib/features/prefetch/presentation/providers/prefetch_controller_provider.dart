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
/// unrelated rebuilds; the read history is read once at creation.
final prefetchControllerProvider =
    StateNotifierProvider.family<PrefetchController, PrefetchState, String>((
      ref,
      novelKey,
    ) {
      final novels =
          ref.read(readNovelsProvider).valueOrNull ?? const <ReadNovel>[];

      ReadNovel? seed;
      for (final novel in novels) {
        if (novel.key == novelKey) {
          seed = novel;
          break;
        }
      }

      return PrefetchController(
        novelKey: novelKey,
        seed: seed,
        scraper: ref.read(scraperRepositoryProvider),
        store: ref.read(offlineChapterStoreProvider),
      );
    });

/// What the prefetch page shows for one novel.
class PrefetchState {
  const PrefetchState({
    this.savedCount = 0,
    this.savedTitles = const [],
    this.isFetching = false,
    this.fetchedCount = 0,
    this.hasNextBatch = true,
    this.error,
    this.ready = false,
  });

  /// Chapters already stored on the device for this novel.
  final int savedCount;

  /// Titles of [savedCount], in reading order.
  final List<String> savedTitles;

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
      isFetching: isFetching ?? this.isFetching,
      fetchedCount: fetchedCount ?? this.fetchedCount,
      hasNextBatch: hasNextBatch ?? this.hasNextBatch,
      error: clearError ? null : (error ?? this.error),
      ready: ready ?? this.ready,
    );
  }
}

/// Saves batches of chapters from a novel's chain to local storage.
class PrefetchController extends StateNotifier<PrefetchState> {
  PrefetchController({
    required this.novelKey,
    required this.seed,
    required this.scraper,
    required this.store,
  }) : super(const PrefetchState()) {
    _restore();
  }

  final String novelKey;

  /// The chapter the user read most recently, seeding the first
  /// batch before anything has been saved.
  final ReadNovel? seed;
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
      hasNextBatch: saved.isEmpty || saved.last.nextChapterUrl != null,
      clearError: true,
    );
  }

  /// Saves up to [prefetchBatchSize] more chapters, starting after
  /// the last saved one — or at the chapter the user read last when
  /// nothing is saved yet.
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
      hasNextBatch:
          _saved.isEmpty
              ? state.hasNextBatch
              : _saved.last.nextChapterUrl != null,
      error: failure == null ? null : _messageOf(failure),
    );
  }

  String? _nextStartUrl() {
    if (_saved.isNotEmpty) return _saved.last.nextChapterUrl;
    return seed?.url;
  }

  static final RegExp _errorPrefix = RegExp(
    r'^(?:[A-Za-z]*Exception|[A-Za-z]*Error):\s*',
  );

  String _messageOf(Object error) {
    final message = error.toString().trim().replaceFirst(_errorPrefix, '');

    return message.isEmpty ? 'Something went wrong' : message;
  }
}
