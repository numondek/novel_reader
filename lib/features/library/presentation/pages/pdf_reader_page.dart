import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../reader/presentation/providers/reader_tts_controller.dart';
import '../../../reader/presentation/widgets/font_size_settings.dart';
import '../../../reader/presentation/widgets/reading_paragraph.dart';
import '../../../reader/presentation/widgets/reader_controls.dart';
import '../../../reader/presentation/widgets/tracker_line.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/models/pdf_document.dart';
import '../providers/pdf_reader_provider.dart';

/// Text reader for library PDFs: chapters are loaded one at a time,
/// narrated like the novel reader and listed in a drawer.
@RoutePage()
class PdfReaderPage extends ConsumerStatefulWidget {
  const PdfReaderPage({
    super.key,
    required this.path,
    required this.title,
    this.initialPage = 1,
  });

  /// Stored file to open.
  final String path;

  final String title;

  /// Page to resume at (1-based).
  final int initialPage;

  @override
  ConsumerState<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends ConsumerState<PdfReaderPage> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _paragraphKeys = <int, GlobalKey>{};
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late final ReaderTtsController _ttsController;
  void Function()? _previousOnFinished;

  /// Chapter to start narrating once its text lands, set when a
  /// chapter finishes so playback continues into the next one.
  int? _pendingAutoPlayIndex;

  PdfReaderController get _controller =>
      ref.read(pdfReaderControllerProvider(widget.path).notifier);

  @override
  void initState() {
    super.initState();

    _ttsController = ref.read(readerTtsControllerProvider.notifier);
    _previousOnFinished = _ttsController.onFinished;
    _ttsController.onFinished = _handleChapterFinished;

    Future.microtask(() => _controller.open(widget.initialPage));
  }

  @override
  void dispose() {
    _ttsController.onFinished = _previousOnFinished;
    _ttsController.stopAll();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleChapterFinished() {
    final state = ref.read(pdfReaderControllerProvider(widget.path));

    if (!state.hasNextChapter) {
      return;
    }

    _pendingAutoPlayIndex = state.chapterIndex + 1;
    _controller.nextChapter();
  }

  void _goNext() {
    _pendingAutoPlayIndex = null;
    _ttsController.stopAll();
    _controller.nextChapter();
  }

  void _goPrevious() {
    _pendingAutoPlayIndex = null;
    _ttsController.stopAll();
    _controller.previousChapter();
  }

  void _selectChapter(int index) {
    _scaffoldKey.currentState?.closeEndDrawer();
    _pendingAutoPlayIndex = null;
    _ttsController.stopAll();
    _controller.openChapter(index);
  }

  @override
  Widget build(BuildContext context) {
    final provider = pdfReaderControllerProvider(widget.path);
    final state = ref.watch(provider);
    final settings = ref.watch(settingsProvider);
    final tts = ref.watch(readerTtsControllerProvider);

    ref.listen(provider, (previous, next) {
      final error = next.error;

      // Chapter failures only: a failure to open the file at all
      // already owns the whole body.
      if (error != null && error != previous?.error && next.document != null) {
        _pendingAutoPlayIndex = null;

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }

      if (next.document != previous?.document ||
          next.chapterIndex != previous?.chapterIndex) {
        _scrollToTop();
      }

      if (_pendingAutoPlayIndex != null &&
          next.chapterIndex == _pendingAutoPlayIndex &&
          next.paragraphs.isNotEmpty &&
          !next.isLoadingDocument &&
          !next.isLoadingChapter &&
          next.error == null) {
        _pendingAutoPlayIndex = null;

        _ttsController.play(
          next.paragraphs,
          title: next.chapter?.displayTitle,
        );
      }
    });

    ref.listen(readerTtsControllerProvider, (previous, next) {
      final indexChanged = next.currentIndex != previous?.currentIndex;
      final startedPlaying = next.isPlaying && previous?.isPlaying != true;

      if ((indexChanged || startedPlaying) &&
          (next.isPlaying || next.isPaused)) {
        _controller.setActiveParagraph(next.currentIndex);
        _scrollToParagraph(next.currentIndex);
      }

      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    if (state.document == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body:
            state.error != null
                ? EmptyState(
                  icon: Icons.error_outline,
                  title: 'Could not open PDF',
                  subtitle: state.error,
                )
                : const Center(child: CircularProgressIndicator()),
      );
    }

    final chapter = state.chapter;
    final paragraphs = state.paragraphs;

    final narrationProgress =
        paragraphs.isNotEmpty && (tts.isPlaying || tts.isPaused)
            ? ((tts.currentIndex + 1) / paragraphs.length)
                .clamp(0.0, 1.0)
                .toDouble()
            : null;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child:
              state.isLoadingDocument || state.isLoadingChapter
                  ? const LinearProgressIndicator(minHeight: 4)
                  : const SizedBox(height: 4),
        ),
        actions: [
          IconButton(
            tooltip: 'Chapters',
            icon: const Icon(Icons.list_alt),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
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
      endDrawer: _buildChapterDrawer(state),
      body: _buildBody(state, chapter, paragraphs),
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
            hasPrevious: state.hasPreviousChapter && !state.isLoadingChapter,
            hasNext: state.hasNextChapter && !state.isLoadingChapter,
            onPrevious: _goPrevious,
            onNext: _goNext,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    PdfReaderState state,
    PdfChapter? chapter,
    List<String> paragraphs,
  ) {
    if (paragraphs.isNotEmpty) {
      final settings = ref.watch(settingsProvider);
      final tts = ref.watch(readerTtsControllerProvider);

      return SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Text(
                chapter?.displayTitle ?? '',
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
                  _controller.setActiveParagraph(index);

                  if (tts.isPlaying || tts.isPaused) {
                    _ttsController.seek(index);
                  }
                },
              ),
            const SizedBox(height: 30),
          ],
        ),
      );
    }

    if (state.error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Could not load chapter',
        subtitle: state.error,
      );
    }

    if (state.isLoadingChapter || state.isLoadingDocument) {
      return const Center(child: CircularProgressIndicator());
    }

    return EmptyState(
      icon: Icons.menu_book_outlined,
      title: 'No text found',
      subtitle: chapter?.displayTitle,
    );
  }

  Widget _buildChapterDrawer(PdfReaderState state) {
    final chapters = state.document?.chapters ?? const [];

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text('Chapters', style: AppTypography.heading),
            ),
            for (var index = 0; index < chapters.length; index++)
              ListTile(
                dense: true,
                selected: index == state.chapterIndex,
                title: Text(chapters[index].displayTitle),
                subtitle: Text('Page ${chapters[index].startPage + 1}'),
                onTap: () => _selectChapter(index),
              ),
          ],
        ),
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

  /// Scrolls so the active paragraph stays a quarter of the way down
  /// the viewport while TTS is reading.
  void _scrollToParagraph(int index) {
    if (!ref.read(settingsProvider).autoScroll) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final paragraphContext = _paragraphKeys[index]?.currentContext;
      if (paragraphContext == null) return;

      final scrollable = Scrollable.of(paragraphContext);
      final box = paragraphContext.findRenderObject();
      final viewport = scrollable.context.findRenderObject();

      if (box is! RenderBox || viewport is! RenderBox) return;
      if (!box.attached ||
          !box.hasSize ||
          !viewport.attached ||
          !viewport.hasSize) {
        return;
      }

      final position = scrollable.position;
      if (!position.hasPixels) return;

      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final bottom = top + box.size.height;

      final media = MediaQuery.of(paragraphContext);
      final bottomLimit = viewport.size.height - 72 - media.padding.bottom - 8;

      if (top >= 0 && bottom <= bottomLimit) return;

      final target =
          (position.pixels + top - viewport.size.height * 0.25)
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble();

      if ((target - position.pixels).abs() < 1) return;

      position.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  void _toggleSpeech(List<String> paragraphs) {
    if (paragraphs.isEmpty) {
      return;
    }

    final tts = ref.read(readerTtsControllerProvider);
    final state = ref.read(pdfReaderControllerProvider(widget.path));

    if (tts.isPlaying) {
      _ttsController.pause();
    } else if (tts.isPaused) {
      _ttsController.resume();
    } else {
      _ttsController.play(
        paragraphs,
        startIndex: state.activeParagraph,
        title: state.chapter?.displayTitle,
      );
    }
  }
}
