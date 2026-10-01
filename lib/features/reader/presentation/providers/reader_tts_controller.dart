import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../translation/domain/language_detector.dart';
import '../../data/services/flutter_text_to_speech.dart';
import '../../domain/services/text_to_speech.dart';

final readerTtsControllerProvider =
    StateNotifierProvider<ReaderTtsController, ReaderTtsState>(
  (ref) {
    final controller = ReaderTtsController(
      tts: FlutterTextToSpeech(),
    );

    ref.onDispose(controller.stopAll);

    return controller;
  },
);

class ReaderTtsState {
  const ReaderTtsState({
    this.isPlaying = false,
    this.isPaused = false,
    this.currentIndex = 0,
    this.error,
  });

  final bool isPlaying;
  final bool isPaused;
  final int currentIndex;
  final String? error;

  ReaderTtsState copyWith({
    bool? isPlaying,
    bool? isPaused,
    int? currentIndex,
    String? error,
  }) {
    return ReaderTtsState(
      isPlaying: isPlaying ?? this.isPlaying,
      isPaused: isPaused ?? this.isPaused,
      currentIndex: currentIndex ?? this.currentIndex,
      error: error,
    );
  }
}

/// Speaks chapter paragraphs one at a time so the reader can follow
/// along, highlighting the paragraph currently being read.
class ReaderTtsController extends StateNotifier<ReaderTtsState> {
  ReaderTtsController({required TextToSpeech tts})
      : _tts = tts,
        super(const ReaderTtsState()) {
    _tts.onCompletion(_handleCompletion);
    _tts.onCancel(_handleCancel);
    _tts.onError(_handleError);
  }

  static const double speechRate = 0.5;

  final TextToSpeech _tts;
  List<String> _paragraphs = const [];

  /// Set by the reader page: called when the last paragraph of a
  /// chapter finishes playing (used for auto-advancing).
  void Function()? onFinished;

  Future<void> play(
    List<String> paragraphs, {
    int startIndex = 0,
  }) async {
    if (paragraphs.isEmpty) {
      return;
    }

    _paragraphs = paragraphs;

    var index = startIndex;
    if (index < 0) index = 0;
    if (index >= paragraphs.length) {
      index = paragraphs.length - 1;
    }

    final language = containsCjk(paragraphs[index])
        ? 'zh-CN'
        : 'en-US';

    await _tts.setLanguage(language);
    await _tts.setSpeechRate(speechRate);

    state = ReaderTtsState(
      isPlaying: true,
      currentIndex: index,
    );
    await _tts.speak(paragraphs[index]);
  }

  Future<void> pause() async {
    if (!state.isPlaying) {
      return;
    }

    await _tts.stop();

    state = state.copyWith(
      isPlaying: false,
      isPaused: true,
    );
  }

  Future<void> resume() async {
    if (!state.isPaused || _paragraphs.isEmpty) {
      return;
    }

    await play(_paragraphs, startIndex: state.currentIndex);
  }

  Future<void> seek(int index) async {
    if (_paragraphs.isEmpty) {
      return;
    }

    await _tts.stop();
    await play(_paragraphs, startIndex: index);
  }

  Future<void> stopAll() async {
    if (state.isPlaying || state.isPaused) {
      await _tts.stop();
    }

    _paragraphs = const [];

    if (mounted) {
      state = const ReaderTtsState();
    }
  }

  void _handleCompletion() {
    if (!state.isPlaying) {
      return;
    }

    final next = state.currentIndex + 1;

    if (next >= _paragraphs.length) {
      stopAll();
      onFinished?.call();
      return;
    }

    state = state.copyWith(currentIndex: next);
    _tts.speak(_paragraphs[next]);
  }

  void _handleCancel() {
    if (state.isPlaying) {
      state = state.copyWith(
        isPlaying: false,
        isPaused: true,
      );
    }
  }

  void _handleError(dynamic message) {
    _paragraphs = const [];

    state = ReaderTtsState(error: '$message');
  }
}
