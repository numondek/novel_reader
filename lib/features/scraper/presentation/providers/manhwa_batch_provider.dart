import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../prefetch/presentation/providers/offline_chapter_store_provider.dart';
import '../../../prefetch/presentation/providers/prefetch_controller_provider.dart';
import '../../data/repositories/scraper_repository.dart';
import '../../data/services/chapter_link_finder.dart';
import '../../data/services/chapter_order.dart';
import '../../domain/services/offline_chapter_store.dart';
import 'scraper_providers.dart';

/// Identifies one shelf card's batch saver: the series it fills and
/// the page its table of contents lives on.
class ManhwaBatchTarget {
  const ManhwaBatchTarget({required this.novelKey, required this.sourceUrl});

  final String novelKey;
  final String sourceUrl;

  @override
  bool operator ==(Object other) {
    return other is ManhwaBatchTarget &&
        other.novelKey == novelKey &&
        other.sourceUrl == sourceUrl;
  }

  @override
  int get hashCode => Object.hash(novelKey, sourceUrl);
}

/// Progress of one "save the next 10" pass.
class ManhwaBatchState {
  const ManhwaBatchState({
    this.isSaving = false,
    this.savedCount = 0,
    this.totalCount = 0,
    this.error,
  });

  final bool isSaving;

  /// Chapters saved by the running pass, out of [totalCount].
  final int savedCount;
  final int totalCount;

  /// The last hiccup, cleared by the next attempt.
  final String? error;

  bool get hasProgress => totalCount > 0;

  ManhwaBatchState copyWith({
    bool? isSaving,
    int? savedCount,
    int? totalCount,
    String? error,
    bool clearError = false,
  }) {
    return ManhwaBatchState(
      isSaving: isSaving ?? this.isSaving,
      savedCount: savedCount ?? this.savedCount,
      totalCount: totalCount ?? this.totalCount,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Fills one shelf card with the chapters it does not have yet,
/// starting right after the last saved one and stopping after
/// [prefetchBatchSize] — the same batch the reader's prefetch page
/// hands out.
final manhwaBatchControllerProvider = StateNotifierProvider.autoDispose
    .family<ManhwaBatchController, ManhwaBatchState, ManhwaBatchTarget>((
      ref,
      target,
    ) {
      return ManhwaBatchController(
        target: target,
        scraper: ref.read(scraperRepositoryProvider),
        store: ref.read(offlineChapterStoreProvider),
      );
    });

class ManhwaBatchController extends StateNotifier<ManhwaBatchState> {
  ManhwaBatchController({
    required this.target,
    required this.scraper,
    required this.store,
  }) : super(const ManhwaBatchState());

  final ManhwaBatchTarget target;
  final ScraperRepository scraper;
  final OfflineChapterStore store;

  /// Downloads the next batch of missing chapters onto the device.
  Future<void> saveNextBatch() async {
    if (state.isSaving) {
      return;
    }

    state = const ManhwaBatchState(isSaving: true);

    try {
      final html = await scraper.loadHtml(target.sourceUrl);
      final links = chaptersInReadingOrder(
        findChapterLinks(html, Uri.parse(target.sourceUrl)),
        title: (link) => link.title,
        url: (link) => link.url,
      );

      if (links.isEmpty) {
        throw StateError('No chapters found on this page.');
      }

      final saved = await store.load(target.novelKey);
      final savedUrls = {for (final chapter in saved) chapter.url};
      final pending = _nextBatch(links, savedUrls);

      if (pending.isEmpty) {
        state = const ManhwaBatchState(error: 'Every chapter is saved.');
        return;
      }

      state = ManhwaBatchState(isSaving: true, totalCount: pending.length);

      var done = 0;

      for (final link in pending) {
        final chapter = await scraper.extractChapter(link.url);
        await store.save(target.novelKey, chapter);

        done += 1;

        if (!mounted) return;

        state = ManhwaBatchState(
          isSaving: true,
          savedCount: done,
          totalCount: pending.length,
        );
      }

      if (!mounted) return;

      state = ManhwaBatchState(savedCount: done, totalCount: pending.length);
    } catch (error) {
      if (!mounted) return;

      state = ManhwaBatchState(error: _messageOf(error));
    }
  }

  /// The chapters to fetch: everything missing, starting just after
  /// the last saved one and wrapping around the list so a series
  /// with a gap in the middle still fills in.
  List<ChapterLink> _nextBatch(List<ChapterLink> links, Set<String> savedUrls) {
    var start = 0;

    for (var index = 0; index < links.length; index++) {
      if (savedUrls.contains(links[index].url)) {
        start = index + 1;
      }
    }

    final pending = <ChapterLink>[];

    for (
      var step = 0;
      step < links.length && pending.length < prefetchBatchSize;
      step++
    ) {
      final link = links[(start + step) % links.length];

      if (!savedUrls.contains(link.url)) {
        pending.add(link);
      }
    }

    return pending;
  }

  static final RegExp _errorPrefix = RegExp(
    r'^(?:[A-Za-z]*Exception|[A-Za-z]*Error):\s*',
  );

  String _messageOf(Object error) {
    final message = error.toString().trim().replaceFirst(_errorPrefix, '');

    return message.isEmpty ? 'Something went wrong' : message;
  }
}
