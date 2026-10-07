import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../prefetch/presentation/providers/offline_chapter_store_provider.dart';
import '../../data/repositories/scraper_repository.dart';
import '../../data/services/chapter_link_finder.dart';
import '../../data/services/chapter_order.dart';
import '../../data/services/series_details_extractor.dart';
import '../../data/services/series_path.dart';
import '../../domain/models/extracted_chapter.dart';
import '../../domain/models/manhwa_series.dart';
import '../../domain/services/offline_chapter_store.dart';
import '../../domain/services/offline_image_store.dart';
import '../providers/manhwa_shelf_provider.dart';
import '../providers/scraper_providers.dart';

/// One chapter of the page the scraper opened.
class ScrapeChapter {
  const ScrapeChapter({
    required this.title,
    required this.url,
    this.saved = false,
  });

  final String title;
  final String url;

  /// Whether the chapter (and its pictures) are on the device.
  final bool saved;

  ScrapeChapter copyWith({bool? saved}) {
    return ScrapeChapter(title: title, url: url, saved: saved ?? this.saved);
  }
}

/// What the scraper page shows for the opened URL.
class ScraperState {
  const ScraperState({
    this.url = '',
    this.novelKey = '',
    this.chapters = const [],
    this.isLoading = false,
    this.isSavingAll = false,
    this.savedCount = 0,
    this.totalCount = 0,
    this.savingUrls = const {},
    this.error,
  });

  /// The series/contents page the list came from.
  final String url;

  /// Groups the saved chapters of this session in the store.
  final String novelKey;

  final List<ScrapeChapter> chapters;
  final bool isLoading;

  /// Whether a "save everything" pass is running.
  final bool isSavingAll;

  /// Chapters saved by the running pass, out of [totalCount].
  final int savedCount;
  final int totalCount;

  /// Chapters currently being downloaded.
  final Set<String> savingUrls;

  /// The last failure, shown until the next action starts.
  final String? error;

  bool get hasChapters => chapters.isNotEmpty;

  int get savedTotal => chapters.where((chapter) => chapter.saved).length;

  ScraperState copyWith({
    String? url,
    String? novelKey,
    List<ScrapeChapter>? chapters,
    bool? isLoading,
    bool? isSavingAll,
    int? savedCount,
    int? totalCount,
    Set<String>? savingUrls,
    String? error,
    bool clearError = false,
  }) {
    return ScraperState(
      url: url ?? this.url,
      novelKey: novelKey ?? this.novelKey,
      chapters: chapters ?? this.chapters,
      isLoading: isLoading ?? this.isLoading,
      isSavingAll: isSavingAll ?? this.isSavingAll,
      savedCount: savedCount ?? this.savedCount,
      totalCount: totalCount ?? this.totalCount,
      savingUrls: savingUrls ?? this.savingUrls,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final scraperControllerProvider =
    StateNotifierProvider<ScraperController, ScraperState>((ref) {
      return ScraperController(
        scraper: ref.read(scraperRepositoryProvider),
        store: ref.read(offlineChapterStoreProvider),
        images: ref.read(offlineImageStoreProvider),
        rememberSeries:
            (series) => ref.read(manhwaSeriesProvider.notifier).record(series),
      );
    });

/// Opens a contents page, downloads its chapters for offline
/// reading and hands them to the reader.
class ScraperController extends StateNotifier<ScraperState> {
  ScraperController({
    required this.scraper,
    required this.store,
    this.images,
    this.rememberSeries,
  }) : super(const ScraperState());

  final ScraperRepository scraper;
  final OfflineChapterStore store;

  /// Stores the cover art the shelf shows on a card.
  final OfflineImageStore? images;

  /// Puts the opened series on the Manhwa page's shelf.
  final Future<void> Function(ManhwaSeries series)? rememberSeries;

  /// Lists the chapters found on [rawUrl]'s page.
  Future<void> open(String rawUrl) async {
    final normalized = _normalize(rawUrl);

    if (normalized == null) {
      state = state.copyWith(
        error:
            rawUrl.trim().isEmpty
                ? 'Enter a URL to open.'
                : 'That does not look like a URL.',
      );
      return;
    }

    var url = normalized;

    state = ScraperState(url: url, isLoading: true);

    try {
      var uri = Uri.parse(url);
      var html = await scraper.loadHtml(url);
      var links = findChapterLinks(html, uri);

      // A chapter page links at most its neighbours, and some link
      // nothing at all. The series behind it holds the whole list,
      // so open that whenever the page proves not to be a contents
      // page — the series of a chapter is already in its URL.
      if (links.length < 4) {
        final series = _seriesUri(uri);

        if (series != null) {
          try {
            final seriesHtml = await scraper.loadHtml(series.toString());
            final seriesLinks = findChapterLinks(seriesHtml, series);

            if (seriesLinks.length > links.length) {
              uri = series;
              html = seriesHtml;
              links = seriesLinks;
              url = series.toString();
            }
          } catch (_) {
            // Whatever the chapter page listed still stands.
          }
        }
      }

      if (links.isEmpty) {
        throw const PageFetchException(
          'No chapters found on this page. '
          'Open a series or chapter contents page.',
        );
      }

      final ordered = chaptersInReadingOrder(
        links,
        title: (link) => link.title,
        url: (link) => link.url,
      );

      final chapters = <ScrapeChapter>[];

      for (final link in ordered) {
        chapters.add(
          ScrapeChapter(
            title: link.title,
            url: link.url,
            saved: await _isSaved(link.url),
          ),
        );
      }

      final novelKey = manhwaNovelKey(uri, links: ordered);

      state = ScraperState(url: url, novelKey: novelKey, chapters: chapters);

      await _shelve(html, uri, novelKey, sourceUrl: url);
    } catch (error) {
      state = ScraperState(url: url, error: _messageOf(error));
    }
  }

  /// Leaves the chapter list and returns to the shelf.
  void close() {
    state = const ScraperState();
  }

  /// Adds the opened series to the shelf with its cover, so the
  /// Manhwa page can offer it again without the URL.
  ///
  /// Everything here is best effort: a missing cover or a storage
  /// hiccup must never turn a successful opening into an error.
  Future<void> _shelve(
    String html,
    Uri pageUrl,
    String novelKey, {
    required String sourceUrl,
  }) async {
    final remember = rememberSeries;
    if (remember == null) return;

    try {
      final details = extractSeriesDetails(html, pageUrl);
      String? coverPath;

      final coverUrl = details.coverUrl;
      final images = this.images;

      if (coverUrl != null && images != null) {
        try {
          coverPath = await images.save(coverUrl, referer: sourceUrl);
        } catch (_) {
          coverPath = null;
        }
      }

      await remember(
        ManhwaSeries(
          novelKey: novelKey,
          title: details.title,
          sourceUrl: sourceUrl,
          coverUrl: coverUrl,
          coverPath: coverPath,
          openedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      // The shelf is a convenience; the chapters are already open.
    }
  }

  /// Downloads one chapter — text and pictures — onto the device.
  Future<void> save(ScrapeChapter target) async {
    if (target.saved || state.savingUrls.isNotEmpty || state.isSavingAll) {
      return;
    }

    state = state.copyWith(savingUrls: {target.url}, clearError: true);

    try {
      final chapter = await scraper.extractChapter(target.url);
      await store.save(state.novelKey, chapter);

      state = state.copyWith(
        savingUrls: const {},
        chapters: _markSaved(target.url),
      );
    } catch (error) {
      state = state.copyWith(savingUrls: const {}, error: _messageOf(error));
    }
  }

  /// Downloads every chapter that is not saved yet, one at a time,
  /// stopping at the first failure.
  Future<void> saveAll() async {
    if (state.isLoading || state.isSavingAll || state.savingUrls.isNotEmpty) {
      return;
    }

    final pending = [
      for (final chapter in state.chapters)
        if (!chapter.saved) chapter,
    ];

    if (pending.isEmpty) {
      return;
    }

    state = state.copyWith(
      isSavingAll: true,
      savedCount: 0,
      totalCount: pending.length,
      clearError: true,
    );

    var done = 0;

    for (final target in pending) {
      if (!mounted) return;

      state = state.copyWith(savingUrls: {...state.savingUrls, target.url});

      try {
        final chapter = await scraper.extractChapter(target.url);
        await store.save(state.novelKey, chapter);

        done += 1;

        state = state.copyWith(
          savedCount: done,
          savingUrls: {...state.savingUrls}..remove(target.url),
          chapters: _markSaved(target.url),
        );
      } catch (error) {
        state = state.copyWith(
          isSavingAll: false,
          savingUrls: const {},
          error: _messageOf(error),
        );
        return;
      }
    }

    if (!mounted) return;

    state = state.copyWith(isSavingAll: false, savedCount: done);
  }

  /// The chapter to open in the reader, or `null` when it could
  /// not be fetched (the failure lands in [ScraperState.error]).
  Future<ExtractedChapter?> readChapter(String url) async {
    try {
      return await scraper.extractChapter(url);
    } catch (error) {
      state = state.copyWith(error: _messageOf(error));
      return null;
    }
  }

  List<ScrapeChapter> _markSaved(String url) {
    return [
      for (final chapter in state.chapters)
        chapter.url == url ? chapter.copyWith(saved: true) : chapter,
    ];
  }

  Future<bool> _isSaved(String url) async {
    try {
      return await store.find(url) != null;
    } catch (_) {
      return false;
    }
  }

  /// The series page [uri]'s chapter hangs from, or `null` when
  /// [uri] already is a contents page — trimming a chapter off the
  /// path is exactly what tells the two apart.
  Uri? _seriesUri(Uri uri) {
    final series = seriesPathOf(uri);

    final segments = [
      for (final segment in series.split('/'))
        if (segment.isNotEmpty) segment,
    ];

    if (segments.isEmpty) {
      return null;
    }

    var path = uri.path;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    if (series == path) {
      return null;
    }

    return uri.replace(path: series, query: null, fragment: null);
  }

  String? _normalize(String rawUrl) {
    var url = rawUrl.trim();

    if (url.isEmpty) {
      return null;
    }

    var uri = Uri.tryParse(url);

    if (uri == null || !uri.hasScheme) {
      uri = Uri.tryParse('https://$url');
      url = uri?.toString() ?? url;
    }

    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }

    return url;
  }

  static final RegExp _errorPrefix = RegExp(
    r'^(?:[A-Za-z]*Exception|[A-Za-z]*Error):\s*',
  );

  static String _messageOf(Object error) {
    final message = error.toString().trim().replaceFirst(_errorPrefix, '');

    return message.isEmpty ? 'Something went wrong' : message;
  }
}
