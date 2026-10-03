import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../translation/domain/language_detector.dart';
import '../../data/services/flutter_text_to_speech.dart';
import '../../domain/services/media_session.dart';
import '../../domain/services/playback_interruptions.dart';
import '../../domain/services/text_to_speech.dart';

final ttsServiceProvider = Provider<TextToSpeech>((ref) {
  return FlutterTextToSpeech();
});

/// The OS media notification / quick settings bridge. Overridden in
/// `main()` with a real audio_service-backed session.
final mediaSessionProvider = Provider<MediaSession>((ref) {
  return const NoopMediaSession();
});

/// The OS audio-focus bridge used to hear other apps start and stop
/// playing. Overridden in `main()` with a real audio_session-backed
/// session.
final playbackInterruptionsProvider = Provider<PlaybackInterruptions>((ref) {
  return const NoopPlaybackInterruptions();
});

final readerTtsControllerProvider =
    StateNotifierProvider<ReaderTtsController, ReaderTtsState>((ref) {
      final controller = ReaderTtsController(
        tts: ref.read(ttsServiceProvider),
        settings: () => ref.read(settingsProvider),
        mediaSession: ref.read(mediaSessionProvider),
        playbackInterruptions: ref.read(playbackInterruptionsProvider),
      );

      ref.onDispose(controller.stopAll);

      return controller;
    });

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
///
/// While narration runs the controller holds audio focus through
/// [PlaybackInterruptions]: another app starting to play steps the
/// narration aside, and it picks up again when that app stops.
class ReaderTtsController extends StateNotifier<ReaderTtsState>
    implements MediaSessionDelegate, PlaybackInterruptionsDelegate {
  ReaderTtsController({
    required TextToSpeech tts,
    AppSettings Function()? settings,
    MediaSession? mediaSession,
    PlaybackInterruptions? playbackInterruptions,
  }) : _tts = tts,
       _settings = settings ?? (() => const AppSettings()),
       _mediaSession = mediaSession ?? const NoopMediaSession(),
       _playbackInterruptions =
           playbackInterruptions ?? const NoopPlaybackInterruptions(),
       super(const ReaderTtsState()) {
    _tts.onCompletion(_handleCompletion);
    _tts.onCancel(_handleCancel);
    _tts.onError(_handleError);
    _mediaSession.setDelegate(this);
    _playbackInterruptions.setDelegate(this);
  }

  static const double speechRate = 0.5;

  /// Longest string handed to the engine in one call. Android caps
  /// speech input at 5000 characters and rejects anything longer
  /// with ERROR_INVALID_REQUEST (-8), so oversized paragraphs are
  /// split well below that.
  static const int maxSpeechChars = 4000;

  final TextToSpeech _tts;
  final AppSettings Function() _settings;
  final MediaSession _mediaSession;
  final PlaybackInterruptions _playbackInterruptions;
  List<String> _paragraphs = const [];

  /// The current paragraph split into engine-sized pieces; engines
  /// fail on empty text and on text past their length limit, so
  /// narration always speaks a verified piece.
  var _chunks = const <String>[];
  var _chunkIndex = 0;

  /// Set when the user (or the media notification) paused, so an
  /// interruption ending does not resume behind their back.
  var _pausedByUser = false;

  /// Set when narration stepped aside for another app's audio, so it
  /// can pick up again when that app stops.
  var _pausedForInterruption = false;

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
    _pausedByUser = false;
    _pausedForInterruption = false;

    var index = startIndex;
    if (index < 0) index = 0;
    if (index >= paragraphs.length) {
      index = paragraphs.length - 1;
    }

    index = _nextSpeakableIndex(index);
    if (index < 0) {
      // Nothing in the chapter is readable text.
      return;
    }

    final language = containsCjk(paragraphs[index]) ? 'zh-CN' : 'en-US';

    await _applyVoiceSettings(language);

    if (title != null) {
      _mediaSession.setChapterTitle(title);
    }

    state = ReaderTtsState(isPlaying: true, currentIndex: index);
    _mediaSession.setPlaying(true);
    await _playbackInterruptions.setActive(true);
    await _speakCurrentChunk();
  }

  /// First paragraph at or after [from] an engine will accept;
  /// blank lines are skipped so narration never hands over an
  /// empty utterance (ERROR_INVALID_REQUEST).
  int _nextSpeakableIndex(int from) {
    for (var index = from; index < _paragraphs.length; index++) {
      if (_paragraphs[index].trim().isNotEmpty) {
        return index;
      }
    }

    return -1;
  }

  Future<void> _speakCurrentChunk() async {
    _chunks = _splitForSpeech(_paragraphs[state.currentIndex]);
    _chunkIndex = 0;

    if (_chunks.isEmpty) {
      return;
    }

    await _tts.speak(_chunks.first);
  }

  /// Splits [text] into pieces the engine accepts, preferring word
  /// boundaries so sentences stay intact across pieces.
  static List<String> _splitForSpeech(String text) {
    if (text.length <= maxSpeechChars) {
      return [text];
    }

    final chunks = <String>[];
    var rest = text;

    while (rest.length > maxSpeechChars) {
      var cut = rest.lastIndexOf(' ', maxSpeechChars);
      if (cut <= 0) cut = maxSpeechChars;

      final chunk = rest.substring(0, cut);
      if (chunk.trim().isNotEmpty) {
        chunks.add(chunk);
      }

      rest = rest.substring(cut).trimLeft();
    }

    if (rest.trim().isNotEmpty) {
      chunks.add(rest);
    }

    return chunks;
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
    return a.split('-').first.toLowerCase() == b.split('-').first.toLowerCase();
  }

  Future<void> pause() async {
    _pausedByUser = true;
    await _stopSpeaking();
  }

  /// Stops the utterance and reports a paused state. Shared by the
  /// user pause and by narration stepping aside for another app,
  /// which is why it never marks the pause as the user's own.
  Future<void> _stopSpeaking() async {
    if (!state.isPlaying) {
      return;
    }

    await _tts.stop();

    state = state.copyWith(isPlaying: false, isPaused: true);
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
    _chunks = const [];
    _chunkIndex = 0;
    _pausedByUser = false;
    _pausedForInterruption = false;

    if (mounted) {
      state = const ReaderTtsState();
    }

    if (wasActive) {
      _mediaSession.hide();
      await _playbackInterruptions.setActive(false);
    }
  }

  void _handleCompletion() {
    if (!state.isPlaying) {
      return;
    }

    // An oversized paragraph arrives in pieces: keep reading the
    // current one until its last piece finishes.
    if (_chunkIndex + 1 < _chunks.length) {
      _chunkIndex += 1;

      if (state.isPlaying) {
        _tts.speak(_chunks[_chunkIndex]);
      }
      return;
    }

    final next = _nextSpeakableIndex(state.currentIndex + 1);

    if (next < 0) {
      stopAll();
      onFinished?.call();
      return;
    }

    final text = _paragraphs[next];
    state = state.copyWith(currentIndex: next);

    final language = containsCjk(text) ? 'zh-CN' : 'en-US';

    _applyVoiceSettings(language).whenComplete(() {
      if (!mounted || !state.isPlaying || state.currentIndex != next) {
        return;
      }

      _speakCurrentChunk();
    });
  }

  void _handleCancel() {
    if (state.isPlaying) {
      state = state.copyWith(isPlaying: false, isPaused: true);
      _mediaSession.setPlaying(false);
    }
  }

  void _handleError(dynamic message) {
    _paragraphs = const [];
    _chunks = const [];
    _chunkIndex = 0;
    _pausedByUser = false;
    _pausedForInterruption = false;

    state = ReaderTtsState(error: _friendlyError(message));
    _mediaSession.hide();
    unawaited(_playbackInterruptions.setActive(false));
  }

  /// Engine failures arrive as plugin plumbing strings like
  /// "Error from TextToSpeech (speak) - -8"; give the reader
  /// something it can act on instead.
  String _friendlyError(dynamic message) {
    final text = '$message'.trim();

    if (text.contains('Error from TextToSpeech')) {
      return 'Text-to-speech failed. Try again, or pick another '
          'voice in Settings.';
    }

    return text.isEmpty ? 'Text-to-speech failed.' : text;
  }

  @override
  void onOtherAudioStarted() {
    if (_pausedByUser) {
      return;
    }

    // Idle readers have nothing to step aside for. A narration the
    // engine already cut still counts, so it can resume later.
    if (!state.isPlaying && !state.isPaused) {
      return;
    }

    _pausedForInterruption = true;
    unawaited(_stopSpeaking());
  }

  @override
  void onOtherAudioEnded() {
    if (!_pausedForInterruption || !mounted) {
      return;
    }

    _pausedForInterruption = false;

    if (_pausedByUser) {
      return;
    }

    unawaited(resume());
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
    _playbackInterruptions.setDelegate(null);
    super.dispose();
  }
}
