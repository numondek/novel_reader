import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_typography.dart';
import '../../../novels/domain/models/read_novel.dart';
import '../../../novels/presentation/providers/read_novels_provider.dart';
import '../../../scraper/domain/models/extracted_chapter.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../providers/reader_controller.dart';
import '../providers/reader_tts_controller.dart';
import '../widgets/font_size_settings.dart';
import '../widgets/reading_paragraph.dart';
import '../widgets/reader_controls.dart';
import '../widgets/tracker_line.dart';

@RoutePage()
class ReaderPage extends ConsumerStatefulWidget {
  final ExtractedChapter? chapter;

  const ReaderPage({super.key, this.chapter});

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _paragraphKeys = <int, GlobalKey>{};

  late final ReaderTtsController _ttsController;
  String? _pendingAutoPlayUrl;

  String? _lastChapterUrl;
  int? _restoredParagraph;
  int? _lastReportedParagraph;
  bool _restoring = false;
  bool _suppressScrollReport = false;

  @override
  void initState() {
    super.initState();

    _ttsController = ref.read(readerTtsControllerProvider.notifier);
    _ttsController.onFinished = _handleChapterFinished;

    _scrollController.addListener(_handleScroll);

    final extracted = widget.chapter;
    if (extracted == null) return;

    Future.microtask(() {
      ref.read(readerControllerProvider.notifier).openChapter(extracted);
    });
  }

  @override
  void dispose() {
    _ttsController.onFinished = null;
    _ttsController.stopAll();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleChapterFinished() {
    final nextUrl = ref.read(readerControllerProvider).chapter?.nextChapterUrl;

    if (nextUrl == null) {
      return;
    }

    _pendingAutoPlayUrl = nextUrl;
    ref.read(readerControllerProvider.notifier).nextChapter();
  }

  void _goNext() {
    _pendingAutoPlayUrl = null;
    _ttsController.stopAll();
    ref.read(readerControllerProvider.notifier).nextChapter();
  }

  void _goPrevious() {
    _pendingAutoPlayUrl = null;
    _ttsController.stopAll();
    ref.read(readerControllerProvider.notifier).previousChapter();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerControllerProvider);
    final chapter = state.chapter;
    final settings = ref.watch(settingsProvider);

    ref.listen(readerControllerProvider, (previous, next) {
      final error = next.error;

      if (error != null && error != previous?.error) {
        _pendingAutoPlayUrl = null;

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }

      final chapter = next.chapter;

      if (chapter != null && chapter.url != previous?.chapter?.url) {
        _lastChapterUrl = chapter.url;
        _restoredParagraph = null;
        _lastReportedParagraph = null;
        _suppressScrollReport = true;
        _scrollToTop();
      }

      if (chapter != null &&
          !next.isLoading &&
          !next.isTranslating &&
          _restoredParagraph == null &&
          !_restoring &&
          _pendingAutoPlayUrl == null) {
        _restoreParagraph(chapter.url);
      }

      if (_pendingAutoPlayUrl != null &&
          chapter != null &&
          chapter.url == _pendingAutoPlayUrl &&
          !next.isLoading &&
          !next.isTranslating) {
        _pendingAutoPlayUrl = null;

        final paragraphs = next.translatedParagraphs ?? chapter.paragraphs;

        _ttsController.play(
          paragraphs,
          title: next.translatedTitle ?? chapter.title,
        );
      }
    });

    ref.listen(readerTtsControllerProvider, (previous, next) {
      final indexChanged = next.currentIndex != previous?.currentIndex;
      final startedPlaying = next.isPlaying && previous?.isPlaying != true;

      if ((indexChanged || startedPlaying) &&
          (next.isPlaying || next.isPaused)) {
        ref
            .read(readerControllerProvider.notifier)
            .setActiveParagraph(next.currentIndex);

        _scrollToParagraph(next.currentIndex);
      }

      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    if (chapter == null) {
      if (widget.chapter != null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }

      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('No chapter available.')),
      );
    }

    final title = state.translatedTitle ?? chapter.title;

    final paragraphs = state.translatedParagraphs ?? chapter.paragraphs;

    final tts = ref.watch(readerTtsControllerProvider);

    final narrationProgress =
        paragraphs.isNotEmpty && (tts.isPlaying || tts.isPaused)
            ? ((tts.currentIndex + 1) / paragraphs.length)
                .clamp(0.0, 1.0)
                .toDouble()
            : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child:
              state.isLoading
                  ? const LinearProgressIndicator(minHeight: 4)
                  : Container(),
        ),
        actions: [
          IconButton(
            onPressed:
                state.isTranslating
                    ? null
                    : () =>
                        ref
                            .read(readerControllerProvider.notifier)
                            .toggleTranslation(),
            tooltip:
                state.translatedParagraphs != null
                    ? 'Show original'
                    : 'Translate to English',
            icon:
                state.isTranslating
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Icon(
                      Icons.translate_outlined,
                      color:
                          state.translatedParagraphs != null
                              ? Theme.of(context).colorScheme.primary
                              : null,
                    ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'font_size') {
                showFontSizeSettings(context, ref);
              }
            },
            itemBuilder:
                (context) => const [
                  PopupMenuItem(value: 'font_size', child: Text('Font size')),
                ],
          ),
        ],
      ),
      resizeToAvoidBottomInset: false,
      extendBody: true,
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: AppTypography.heading,
              ),
            ),
            const SizedBox(height: 32),
            for (var index = 0; index < paragraphs.length; index++)
              ReadingParagraph(
                key: _paragraphKey(index),
                text: paragraphs[index],
                fontSize: settings.fontSize.toDouble(),
                isActive: state.activeParagraph == index,
                onTap: () {
                  ref
                      .read(readerControllerProvider.notifier)
                      .setActiveParagraph(index);

                  if (tts.isPlaying || tts.isPaused) {
                    _ttsController.seek(index);
                  }
                },
              ),
            const SizedBox(height: 30),
          ],
        ),
      ),
      bottomSheet: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TrackerLine(
            scrollController: _scrollController,
            progress: narrationProgress,
          ),
          ReaderControls(
            onFontSize: () => showFontSizeSettings(context, ref),
            isPlaying: tts.isPlaying,
            isPaused: tts.isPaused,
            onPlayPause: () => _toggleSpeech(paragraphs),
            autoScroll: settings.autoScroll,
            onToggleAutoScroll: _toggleAutoScroll,
            hasPrevious: chapter.previousChapterUrl != null && !state.isLoading,
            hasNext: chapter.nextChapterUrl != null && !state.isLoading,
            onPrevious: _goPrevious,
            onNext: _goNext,
          ),
        ],
      ),
    );
  }

  GlobalKey _paragraphKey(int index) {
    return _paragraphKeys.putIfAbsent(index, GlobalKey.new);
  }

  void _toggleAutoScroll() {
    final notifier = ref.read(settingsProvider.notifier);
    final next = !ref.read(settingsProvider).autoScroll;

    notifier.setAutoScroll(next);

    if (next) {
      final tts = ref.read(readerTtsControllerProvider);

      if (tts.isPlaying || tts.isPaused) {
        _scrollToParagraph(tts.currentIndex);
      }
    }
  }

  /// Scrolls so the active paragraph is visible (kept around a
  /// quarter of the way down the viewport) while TTS is reading.
  void _scrollToParagraph(int index) {
    if (!ref.read(settingsProvider).autoScroll) {
      return;
    }

    _scrollToIndex(index, animate: true);
  }

  /// Jumps (without animation) to the stored position when a saved
  /// chapter is reopened, then unsuppresses scroll reporting.
  void _jumpToParagraph(int index) {
    final url = _lastChapterUrl;

    _scrollToIndex(
      index,
      animate: false,
      onComplete: () {
        if (_lastChapterUrl != url) {
          // A newer chapter owns suppression now.
          return;
        }

        _lastReportedParagraph = _topmostParagraph() ?? index;
        _suppressScrollReport = false;
      },
    );
  }

  void _scrollToIndex(
    int index, {
    required bool animate,
    VoidCallback? onComplete,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final paragraphContext = _paragraphKeys[index]?.currentContext;
      if (paragraphContext == null) {
        onComplete?.call();
        return;
      }

      final scrollable = Scrollable.of(paragraphContext);

      final box = paragraphContext.findRenderObject();
      final viewport = scrollable.context.findRenderObject();
      if (box is! RenderBox || viewport is! RenderBox) {
        onComplete?.call();
        return;
      }
      if (!box.attached ||
          !box.hasSize ||
          !viewport.attached ||
          !viewport.hasSize) {
        onComplete?.call();
        return;
      }

      final position = scrollable.position;
      if (!position.hasPixels) {
        onComplete?.call();
        return;
      }

      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final bottom = top + box.size.height;

      final media = MediaQuery.of(paragraphContext);
      final bottomLimit = viewport.size.height - 72 - media.padding.bottom - 8;

      final isVisible = top >= 0 && bottom <= bottomLimit;

      if (animate && isVisible) {
        onComplete?.call();
        return;
      }

      final target = (position.pixels + top - viewport.size.height * 0.25)
          .clamp(position.minScrollExtent, position.maxScrollExtent);

      if (animate && (target - position.pixels).abs() < 1) {
        onComplete?.call();
        return;
      }

      if (animate) {
        position.animateTo(
          target.toDouble(),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        onComplete?.call();
        return;
      }

      position.jumpTo(target.toDouble());

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        onComplete?.call();
      });
    });
  }

  /// Reopens a saved chapter at the paragraph the user stopped at.
  ///
  /// Runs once per chapter, after loading and translation settle so
  /// the restored offset matches the final layout.
  Future<void> _restoreParagraph(String url) async {
    _restoring = true;

    try {
      final entries = await ref.read(readNovelsProvider.future);

      if (!mounted) return;

      final current = ref.read(readerControllerProvider).chapter;
      if (current == null || current.url != url || _lastChapterUrl != url) {
        // A newer chapter took over; its own restore decides.
        return;
      }

      ReadNovel? saved;
      for (final entry in entries) {
        if (entry.url == url) {
          saved = entry;
          break;
        }
      }

      final index = saved?.paragraphIndex ?? 0;
      _restoredParagraph = index;

      if (index <= 0) {
        _suppressScrollReport = false;
        return;
      }

      _lastReportedParagraph = index;
      ref.read(readerControllerProvider.notifier).setActiveParagraph(index);
      _jumpToParagraph(index);
    } catch (_) {
      if (_lastChapterUrl == url) {
        _restoredParagraph = 0;
        _suppressScrollReport = false;
      }
    } finally {
      _restoring = false;
    }
  }

  /// Persists the paragraph at the reading line whenever the user
  /// scrolls, so the app can resume where they stopped.
  void _handleScroll() {
    if (!mounted || _suppressScrollReport) return;

    final chapter = ref.read(readerControllerProvider).chapter;
    if (chapter == null) return;

    final index = _topmostParagraph();
    if (index == null || index == _lastReportedParagraph) {
      return;
    }

    _lastReportedParagraph = index;
    ref.read(readerControllerProvider.notifier).reportParagraph(index);
  }

  /// Index of the last paragraph that has crossed the reading line
  /// (a quarter of the way down the viewport).
  int? _topmostParagraph() {
    if (_paragraphKeys.isEmpty) return null;

    int? result;

    for (final entry in _paragraphKeys.entries) {
      final context = entry.value.currentContext;
      if (context == null) continue;

      final box = context.findRenderObject();
      final scrollable = Scrollable.of(context);
      final viewport = scrollable.context.findRenderObject();

      if (box is! RenderBox || viewport is! RenderBox) continue;
      if (!box.attached ||
          !box.hasSize ||
          !viewport.attached ||
          !viewport.hasSize) {
        continue;
      }

      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;

      if (top <= viewport.size.height * 0.25 + 1) {
        result = entry.key;
      } else {
        break;
      }
    }

    return result;
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  void _toggleSpeech(List<String> paragraphs) {
    final tts = ref.read(readerTtsControllerProvider);
    final reader = ref.read(readerControllerProvider);
    final activeParagraph = reader.activeParagraph;

    if (tts.isPlaying) {
      _ttsController.pause();
    } else if (tts.isPaused) {
      _ttsController.resume();
    } else {
      _ttsController.play(
        paragraphs,
        startIndex: activeParagraph,
        title: reader.translatedTitle ?? reader.chapter?.title,
      );
    }
  }
}
