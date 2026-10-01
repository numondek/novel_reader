/// The OS-facing playback surface: media notification, quick settings
/// tile, lock screen and headset buttons.
///
/// Playback changes inside the app are pushed out through
/// [setChapterTitle], [setPlaying] and [hide]; commands coming back
/// from the OS are delivered to a [MediaSessionDelegate].
abstract class MediaSession {
  /// Receives playback commands issued from outside the app.
  /// Pass `null` to drop them (e.g. when the reader is disposed).
  void setDelegate(MediaSessionDelegate? delegate);

  /// Shows or updates what the notification displays.
  void setChapterTitle(String title, {String? subtitle});

  /// Marks narration as running or paused so the OS can show the
  /// right controls and keep the foreground service alive.
  void setPlaying(bool playing);

  /// Dismisses the notification by reporting idle playback.
  void hide();
}

/// Playback commands that originate from the OS rather than the app.
abstract class MediaSessionDelegate {
  Future<void> onPlay();
  Future<void> onPause();
  Future<void> onStop();
  Future<void> onSkipNext();
  Future<void> onSkipPrevious();
}

/// A [MediaSession] that does nothing — the default in tests and on
/// platforms without an audio_service implementation.
class NoopMediaSession implements MediaSession {
  const NoopMediaSession();

  @override
  void setDelegate(MediaSessionDelegate? delegate) {}

  @override
  void setChapterTitle(String title, {String? subtitle}) {}

  @override
  void setPlaying(bool playing) {}

  @override
  void hide() {}
}
