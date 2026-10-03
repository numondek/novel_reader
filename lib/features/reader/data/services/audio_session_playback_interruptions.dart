import 'dart:async';

import 'package:audio_session/audio_session.dart';

import '../../domain/services/playback_interruptions.dart';

/// A [PlaybackInterruptions] backed by the platform audio session: the
/// app holds audio focus while narration runs, so another app
/// starting or stopping playback surfaces here as focus events.
class AudioSessionPlaybackInterruptions implements PlaybackInterruptions {
  AudioSessionPlaybackInterruptions._(this._session);

  final AudioSession _session;

  StreamSubscription<AudioInterruptionEvent>? _subscription;
  PlaybackInterruptionsDelegate? _delegate;

  /// Creates the app-wide instance used by `main()`.
  static Future<PlaybackInterruptions> create() async {
    final session = await AudioSession.instance;
    return AudioSessionPlaybackInterruptions._(session);
  }

  @override
  void setDelegate(PlaybackInterruptionsDelegate? delegate) {
    _delegate = delegate;

    if (delegate != null && _subscription == null) {
      _subscription = _session.interruptionEventStream.listen(_onEvent);
    } else if (delegate == null) {
      _subscription?.cancel();
      _subscription = null;
    }
  }

  void _onEvent(AudioInterruptionEvent event) {
    // A duck only asks us to get quieter, so narration keeps going.
    if (event.type == AudioInterruptionType.duck) {
      return;
    }

    if (event.begin) {
      _delegate?.onOtherAudioStarted();
    } else {
      _delegate?.onOtherAudioEnded();
    }
  }

  @override
  Future<void> setActive(bool active) async {
    try {
      await _session.setActive(active);
    } catch (_) {
      // Focus is a nicety: narration keeps working without it, just
      // without the stepping aside.
    }
  }
}
