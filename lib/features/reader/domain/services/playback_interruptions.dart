/// Lets narration cooperate with audio played by other apps: it
/// steps aside when another app starts playing and picks up again
/// when that app stops.
abstract class PlaybackInterruptions {
  /// Receives reports about other apps' audio. Pass `null` to drop
  /// them (e.g. when the reader is disposed).
  void setDelegate(PlaybackInterruptionsDelegate? delegate);

  /// Joins (`true`) or leaves (`false`) the OS audio focus, which is
  /// what makes [setDelegate] hear anything: focus is held while
  /// narration runs and released when it stops.
  Future<void> setActive(bool active);
}

/// Audio playback changes that happen outside the app.
abstract class PlaybackInterruptionsDelegate {
  /// Another app started playing audio.
  void onOtherAudioStarted();

  /// That app stopped, handing audio back.
  void onOtherAudioEnded();
}

/// A [PlaybackInterruptions] that does nothing — the default in tests
/// and on platforms without an audio_session implementation.
class NoopPlaybackInterruptions implements PlaybackInterruptions {
  const NoopPlaybackInterruptions();

  @override
  void setDelegate(PlaybackInterruptionsDelegate? delegate) {}

  @override
  Future<void> setActive(bool active) async {}
}
