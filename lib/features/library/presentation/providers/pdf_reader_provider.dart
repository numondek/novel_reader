import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/syncfusion_pdf_document_loader.dart';
import '../../domain/models/pdf_document.dart';
import '../../domain/services/pdf_document_loader.dart';
import 'pdf_library_provider.dart';

/// Opens PDFs on demand for the reader; one instance is shared by
/// every open document so only a single file stays in memory.
final pdfDocumentLoaderProvider = Provider<PdfDocumentLoader>((ref) {
  final loader = SyncfusionPdfDocumentLoader();
  ref.onDispose(loader.close);
  return loader;
});

/// Reader state for one file, keyed by its path: which chapter is
/// showing, its paragraphs and the loading progress.
final pdfReaderControllerProvider =
    StateNotifierProvider.family<PdfReaderController, PdfReaderState, String>((
      ref,
      path,
    ) {
      final loader = ref.read(pdfDocumentLoaderProvider);

      return PdfReaderController(
        path: path,
        loader: loader,
        onChapterOpen: (page, pageCount) {
          try {
            ref
                .read(pdfLibraryProvider.notifier)
                .savePosition(path, page: page, pageCount: pageCount);
          } catch (_) {
            // Best effort: reading on without persisting is fine.
          }
        },
      );
    });

class PdfReaderState {
  const PdfReaderState({
    this.document,
    this.chapterIndex = 0,
    this.paragraphs = const [],
    this.isLoadingDocument = false,
    this.isLoadingChapter = false,
    this.activeParagraph = 0,
    this.error,
  });

  final PdfDocumentInfo? document;

  /// Index into [PdfDocumentInfo.chapters] of the visible chapter.
  final int chapterIndex;

  final List<String> paragraphs;
  final bool isLoadingDocument;
  final bool isLoadingChapter;

  /// Paragraph TTS is on, highlighted in the text.
  final int activeParagraph;
  final String? error;

  PdfChapter? get chapter {
    final chapters = document?.chapters;
    if (chapters == null ||
        chapterIndex < 0 ||
        chapterIndex >= chapters.length) {
      return null;
    }
    return chapters[chapterIndex];
  }

  bool get hasNextChapter {
    final chapters = document?.chapters;
    return chapters != null && chapterIndex + 1 < chapters.length;
  }

  bool get hasPreviousChapter => chapterIndex > 0;

  PdfReaderState copyWith({
    PdfDocumentInfo? document,
    int? chapterIndex,
    List<String>? paragraphs,
    bool? isLoadingDocument,
    bool? isLoadingChapter,
    int? activeParagraph,
    String? error,
    bool clearError = false,
  }) {
    return PdfReaderState(
      document: document ?? this.document,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      paragraphs: paragraphs ?? this.paragraphs,
      isLoadingDocument: isLoadingDocument ?? this.isLoadingDocument,
      isLoadingChapter: isLoadingChapter ?? this.isLoadingChapter,
      activeParagraph: activeParagraph ?? this.activeParagraph,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Loads a PDF chapter by chapter: structure once, then only the
/// text of the chapter being read.
class PdfReaderController extends StateNotifier<PdfReaderState> {
  PdfReaderController({
    required this.path,
    required this.loader,
    this.onChapterOpen,
  }) : super(const PdfReaderState());

  final String path;
  final PdfDocumentLoader loader;

  /// Called whenever a chapter becomes the visible one so the
  /// caller can remember where the reader stopped.
  final void Function(int page, int pageCount)? onChapterOpen;

  var _opened = false;

  /// Bumped per chapter load so a slow, superseded request cannot
  /// overwrite the chapter the user moved on to.
  var _token = 0;

  /// Opens the file and lands on the chapter holding [initialPage]
  /// (1-based).
  Future<void> open(int initialPage) async {
    if (_opened) {
      return;
    }
    _opened = true;

    state = state.copyWith(isLoadingDocument: true, clearError: true);

    try {
      final info = await loader.open(path);

      state = state.copyWith(
        document: info,
        chapterIndex: _chapterIndexForPage(info, initialPage),
        isLoadingDocument: false,
        clearError: true,
      );

      await _loadChapter(state.chapterIndex);
    } catch (error) {
      state = state.copyWith(
        isLoadingDocument: false,
        isLoadingChapter: false,
        error: _messageOf(error),
      );
    }
  }

  /// Shows [index], loading only that chapter's paragraphs.
  Future<void> openChapter(int index) async {
    final info = state.document;
    if (info == null || index < 0 || index >= info.chapters.length) {
      return;
    }

    if (index == state.chapterIndex &&
        !state.isLoadingChapter &&
        state.error == null) {
      return;
    }

    state = state.copyWith(
      chapterIndex: index,
      paragraphs: const [],
      isLoadingChapter: true,
      activeParagraph: 0,
      clearError: true,
    );

    await _loadChapter(index);
  }

  Future<void> nextChapter() => openChapter(state.chapterIndex + 1);

  Future<void> previousChapter() => openChapter(state.chapterIndex - 1);

  void setActiveParagraph(int index) {
    if (state.activeParagraph == index) {
      return;
    }

    state = state.copyWith(activeParagraph: index);
  }

  Future<void> _loadChapter(int index) async {
    final info = state.document;
    if (info == null || index < 0 || index >= info.chapters.length) {
      return;
    }

    final chapter = info.chapters[index];
    final token = ++_token;

    onChapterOpen?.call(chapter.startPage + 1, info.pageCount);

    state = state.copyWith(isLoadingChapter: true, clearError: true);

    try {
      final paragraphs = await loader.loadParagraphs(path, chapter);

      if (!mounted || token != _token) {
        return;
      }

      state = state.copyWith(
        paragraphs: paragraphs,
        isLoadingChapter: false,
        activeParagraph: 0,
        clearError: true,
      );
    } catch (error) {
      if (!mounted || token != _token) {
        return;
      }

      state = state.copyWith(
        paragraphs: const [],
        isLoadingChapter: false,
        activeParagraph: 0,
        error: _messageOf(error),
      );
    }
  }

  int _chapterIndexForPage(PdfDocumentInfo info, int initialPage) {
    if (info.chapters.isEmpty) {
      return 0;
    }

    final pageIndex = initialPage < 1 ? 0 : initialPage - 1;

    for (var index = 0; index < info.chapters.length; index++) {
      if (info.chapters[index].contains(pageIndex)) {
        return index;
      }
    }

    return 0;
  }

  String _messageOf(Object error) {
    final message = error.toString().trim().replaceFirst(_errorPrefix, '');
    return message.isEmpty ? 'Something went wrong' : message;
  }

  static final RegExp _errorPrefix = RegExp(
    r'^(?:[A-Za-z]*Exception|[A-Za-z]*Error):\s*',
  );
}
