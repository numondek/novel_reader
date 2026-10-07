import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../novels/domain/models/chapter.dart';
import '../../../novels/presentation/providers/read_novels_provider.dart';
import '../../../scraper/data/repositories/scraper_repository.dart';
import '../../../scraper/domain/models/extracted_chapter.dart';
import '../../../scraper/presentation/providers/scraper_providers.dart';
import '../../../translation/domain/language_detector.dart';
import '../../../translation/domain/services/translation_service.dart';
import '../../../translation/presentation/providers/translation_providers.dart';

final readerControllerProvider =
    StateNotifierProvider<ReaderController, ReaderState>((ref) {
      return ReaderController(
        translator: ref.read(translationServiceProvider),
        scraper: ref.read(scraperRepositoryProvider),
        onChapterRead: (chapter, novelTitle, paragraphIndex) {
          unawaited(
            ref
                .read(readNovelsProvider.notifier)
                .record(
                  chapter.url,
                  chapter.title,
                  novelTitle: novelTitle,
                  paragraphIndex: paragraphIndex,
                  paragraphCount:
                      chapter.hasImages
                          ? chapter.imageUrls.length
                          : chapter.paragraphs.length,
                  manhwaKey:
                      chapter.hasImages ? seriesKeyOf(chapter.url) : null,
                ),
          );
        },
      );
    });

class ReaderState {
  final Chapter? chapter;
  final String? translatedTitle;
  final List<String>? translatedParagraphs;
  final bool isLoading;
  final bool isTranslating;
  final String? error;
  final int activeParagraph;

  const ReaderState({
    this.chapter,
    this.translatedTitle,
    this.translatedParagraphs,
    this.isLoading = false,
    this.isTranslating = false,
    this.error,
    this.activeParagraph = 0,
  });

  ReaderState copyWith({
    Chapter? chapter,
    String? translatedTitle,
    List<String>? translatedParagraphs,
    bool? isLoading,
    bool? isTranslating,
    String? error,
    int? activeParagraph,
  }) {
    return ReaderState(
      chapter: chapter ?? this.chapter,
      translatedTitle: translatedTitle ?? this.translatedTitle,
      translatedParagraphs: translatedParagraphs ?? this.translatedParagraphs,
      isLoading: isLoading ?? this.isLoading,
      isTranslating: isTranslating ?? this.isTranslating,
      error: error,
      activeParagraph: activeParagraph ?? this.activeParagraph,
    );
  }
}

class ReaderController extends StateNotifier<ReaderState> {
  ReaderController({
    required this.translator,
    required this.scraper,
    this.onChapterRead,
  }) : super(const ReaderState());

  final TranslationService translator;
  final ScraperRepository scraper;

  /// Called whenever reading progress changes so the read-novel
  /// history can be updated. [paragraphIndex] is null when a chapter
  /// was just opened (position preserved or reset), or the paragraph
  /// the reader is currently at.
  final void Function(Chapter chapter, String? novelTitle, int? paragraphIndex)?
  onChapterRead;

  String? _novelTitle;

  void openChapter(ExtractedChapter extracted) {
    _novelTitle = extracted.novelTitle;

    final chapter = Chapter(
      id: extracted.url,
      url: extracted.url,
      title: extracted.title,
      paragraphs: extracted.paragraphs,
      previousChapterUrl: extracted.previousChapterUrl,
      nextChapterUrl: extracted.nextChapterUrl,
      imageUrls: extracted.imageUrls,
      offlineImagePaths: extracted.offlineImagePaths,
      status: ChapterStatus.reading,
    );

    onChapterRead?.call(chapter, extracted.novelTitle, null);

    final sample = [chapter.title, ...chapter.paragraphs.take(5)].join('\n');

    // Picture chapters have nothing to translate or narrate.
    final shouldTranslate = !chapter.hasImages && containsCjk(sample);

    state = ReaderState(
      chapter:
          shouldTranslate
              ? chapter.copyWith(status: ChapterStatus.translating)
              : chapter,
      isTranslating: shouldTranslate,
    );

    if (shouldTranslate) {
      translateChapter(chapter);
    }
  }

  Future<void> openUrl(String url) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final extracted = await scraper.extractChapter(url);
      openChapter(extracted);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> nextChapter() async {
    final url = state.chapter?.nextChapterUrl;

    if (url != null) {
      await openUrl(url);
    }
  }

  Future<void> previousChapter() async {
    final url = state.chapter?.previousChapterUrl;

    if (url != null) {
      await openUrl(url);
    }
  }

  Future<void> translateChapter(Chapter chapter) async {
    state = state.copyWith(
      chapter: chapter.copyWith(status: ChapterStatus.translating),
      isTranslating: true,
      error: null,
    );

    try {
      final results = await Future.wait([
        translator.translateParagraphs([chapter.title], targetLanguage: 'en'),
        translator.translateParagraphs(
          chapter.paragraphs,
          targetLanguage: 'en',
        ),
      ]);

      final titleResult = results[0];
      final paragraphs = results[1];

      state = state.copyWith(
        chapter: chapter.copyWith(status: ChapterStatus.ready),
        translatedTitle: titleResult.isNotEmpty ? titleResult.first : null,
        translatedParagraphs: paragraphs,
        isTranslating: false,
      );
    } catch (e) {
      state = state.copyWith(
        chapter: chapter.copyWith(status: ChapterStatus.reading),
        isTranslating: false,
        error: e.toString(),
      );
    }
  }

  void toggleTranslation() {
    if (state.isTranslating) {
      return;
    }

    if (state.translatedParagraphs != null) {
      state = ReaderState(
        chapter: state.chapter?.copyWith(status: ChapterStatus.reading),
        activeParagraph: state.activeParagraph,
      );
      return;
    }

    final chapter = state.chapter;
    if (chapter != null) {
      translateChapter(chapter);
    }
  }

  void setActiveParagraph(int index) {
    state = state.copyWith(activeParagraph: index);

    _reportPosition(index);
  }

  /// Persists the paragraph the reader is looking at (driven by
  /// scrolling) without changing the highlighted active paragraph.
  void reportParagraph(int index) {
    _reportPosition(index);
  }

  void _reportPosition(int index) {
    final chapter = state.chapter;
    final callback = onChapterRead;

    if (chapter == null || callback == null) {
      return;
    }

    callback(chapter, _novelTitle, index);
  }

  void reset() {
    state = const ReaderState();
  }
}
