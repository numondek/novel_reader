import 'package:audio_service/audio_service.dart';

import '../../domain/services/media_session.dart';

/// Routes OS media commands (notification, quick settings, headset,
/// lock screen) to the reader's [MediaSessionDelegate].
class ReaderAudioHandler extends BaseAudioHandler {
  MediaSessionDelegate? _delegate;

  void setDelegate(MediaSessionDelegate? delegate) => _delegate = delegate;

  @override
  Future<void> play() async => _delegate?.onPlay();

  @override
  Future<void> pause() async => _delegate?.onPause();

  @override
  Future<void> stop() async {
    final delegate = _delegate;
    if (delegate == null) {
      await super.stop();
      return;
    }
    await delegate.onStop();
  }

  @override
  Future<void> skipToNext() async => _delegate?.onSkipNext();

  @override
  Future<void> skipToPrevious() async => _delegate?.onSkipPrevious();
}

/// Pushes reader playback state to the media notification and quick
/// settings through audio_service, and receives commands in return.
class AudioServiceMediaSession implements MediaSession {
  AudioServiceMediaSession(this._handler);

  final ReaderAudioHandler _handler;

  @override
  void setDelegate(MediaSessionDelegate? delegate) =>
      _handler.setDelegate(delegate);

  @override
  void setChapterTitle(String title, {String? subtitle}) {
    _handler.mediaItem.add(
      MediaItem(id: title, title: title, artist: subtitle, album: subtitle),
    );
  }

  @override
  void setPlaying(bool playing) {
    _handler.playbackState.add(
      PlaybackState(
        playing: playing,
        processingState: AudioProcessingState.ready,
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        androidCompactActionIndices: const [0, 1, 2],
      ),
    );
  }

  @override
  void hide() {
    _handler.playbackState.add(
      PlaybackState(processingState: AudioProcessingState.idle),
    );
    _handler.mediaItem.add(null);
  }
}

/// Registers the app's audio handler so the OS can control narration
/// from outside the app.
///
/// Falls back to a no-op session where audio_service has no platform
/// implementation (unit tests, desktop targets).
Future<MediaSession> createAudioServiceMediaSession() async {
  final handler = ReaderAudioHandler();

  try {
    await AudioService.init(
      builder: () => handler,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'novel_reader.playback',
        androidNotificationChannelName: 'Playback',
        // Keep the foreground service alive while paused so play can
        // resume it from the background on Android 12+.
        androidStopForegroundOnPause: false,
      ),
    );
  } catch (_) {
    return const NoopMediaSession();
  }

  return AudioServiceMediaSession(handler);
}
