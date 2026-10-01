import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../translation/domain/language_detector.dart';
import '../../data/services/flutter_text_to_speech.dart';
import '../../domain/services/media_session.dart';
import '../../domain/services/text_to_speech.dart';

final ttsServiceProvider = Provider<TextToSpeech>((ref) {
  return FlutterTextToSpeech();
});

/// The OS media notification / quick settings bridge. Overridden in
/// `main()` with a real audio_service-backed session.
final mediaSessionProvider = Provider<MediaSession>((ref) {
  return const NoopMediaSession();
});

final readerTtsControllerProvider =
    StateNotifierProvider<ReaderTtsController, ReaderTtsState>(
  (ref) {
    final controller = ReaderTtsController(
      tts: ref.read(ttsServiceProvider),
      settings: () => ref.read(settingsProvider),
      mediaSession: ref.read(mediaSessionProvider),
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
///
/// Also mirrors its state to the OS [MediaSession] so narration can
/// keep running in the background and be controlled from the media
/// notification, quick settings, lock screen and headset buttons.
class ReaderTtsController extends StateNotifier<ReaderTtsState>
    implements MediaSessionDelegate {
  ReaderTtsController({
    required TextToSpeech tts,
    AppSettings Function()? settings,
    MediaSession? mediaSession,
  })  : _tts = tts,
        _settings = settings ?? (() => const AppSettings()),
        _mediaSession = mediaSession ?? const NoopMediaSession(),
        super(const ReaderTtsState()) {
    _tts.onCompletion(_handleCompletion);
    _tts.onCancel(_handleCancel);
    _tts.onError(_handleError);
    _mediaSession.setDelegate(this);
  }

  static const double speechRate = 0.5;

  final TextToSpeech _tts;
  final AppSettings Function() _settings;
  final MediaSession _mediaSession;
  List<String> _paragraphs = const [];

  /// Set by the reader page: called when the last paragraph of a
  /// chapter finishes playing (used for auto-advancing).
  void Function()? onFinished;

  Future<void> play(
    List<String> paragraphs, {
    int startIndex = 0,
    String? title,
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

    await _applyVoiceSettings(language);

    if (title != null) {
      _mediaSession.setChapterTitle(title);
    }

    state = ReaderTtsState(
      isPlaying: true,
      currentIndex: index,
    );
    _mediaSession.setPlaying(true);
    await _tts.speak(paragraphs[index]);
  }

  /// Applies the user's rate and voice preferences, falling back to
  /// the language default when no voice matches the language.
  Future<void> _applyVoiceSettings(String language) async {
    final settings = _settings();

    await _tts.setLanguage(language);
    await _tts.setSpeechRate(settings.speechRate);

    final name = settings.voiceName;
    if (name == null || name.isEmpty) {
      return;
    }

    final locale = settings.voiceLocale ?? '';
    if (locale.isNotEmpty && !_sameLanguage(locale, language)) {
      // The chosen voice cannot read this language.
      return;
    }

    try {
      await _tts.setVoice(name, locale);
    } catch (_) {
      // Voice unavailable: keep the language default.
    }
  }

  bool _sameLanguage(String a, String b) {
    return a.split('-').first.toLowerCase() ==
        b.split('-').first.toLowerCase();
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
    _mediaSession.setPlaying(false);
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
    final wasActive = state.isPlaying || state.isPaused;

    if (wasActive) {
      await _tts.stop();
    }

    _paragraphs = const [];

    if (mounted) {
      state = const ReaderTtsState();
    }

    if (wasActive) {
      _mediaSession.hide();
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

    final text = _paragraphs[next];
    state = state.copyWith(currentIndex: next);

    final language =
        containsCjk(text) ? 'zh-CN' : 'en-US';

    _applyVoiceSettings(language).whenComplete(() {
      if (!mounted ||
          !state.isPlaying ||
          state.currentIndex != next) {
        return;
      }

      _tts.speak(text);
    });
  }

  void _handleCancel() {
    if (state.isPlaying) {
      state = state.copyWith(
        isPlaying: false,
        isPaused: true,
      );
      _mediaSession.setPlaying(false);
    }
  }

  void _handleError(dynamic message) {
    _paragraphs = const [];

    state = ReaderTtsState(error: '$message');
    _mediaSession.hide();
  }

  @override
  Future<void> onPlay() => resume();

  @override
  Future<void> onPause() => pause();

  @override
  Future<void> onStop() => stopAll();

  @override
  Future<void> onSkipNext() => seek(state.currentIndex + 1);

  @override
  Future<void> onSkipPrevious() => seek(state.currentIndex - 1);

  @override
  void dispose() {
    _mediaSession.setDelegate(null);
    super.dispose();
  }
}
