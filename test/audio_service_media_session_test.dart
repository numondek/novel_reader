import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/reader/data/services/audio_service_media_session.dart';
import 'package:novel_reader/features/reader/domain/services/media_session.dart';

class _FakeDelegate implements MediaSessionDelegate {
  int play = 0;
  int pause = 0;
  int stop = 0;
  int next = 0;
  int previous = 0;

  @override
  Future<void> onPlay() async => play += 1;

  @override
  Future<void> onPause() async => pause += 1;

  @override
  Future<void> onStop() async => stop += 1;

  @override
  Future<void> onSkipNext() async => next += 1;

  @override
  Future<void> onSkipPrevious() async => previous += 1;
}

void main() {
  late ReaderAudioHandler handler;
  late AudioServiceMediaSession session;

  setUp(() {
    handler = ReaderAudioHandler();
    session = AudioServiceMediaSession(handler);
  });

  test('chapter title and playback state reach the handler', () {
    session.setChapterTitle('Chapter 1', subtitle: 'My Novel');
    session.setPlaying(true);

    expect(handler.mediaItem.value?.title, 'Chapter 1');
    expect(handler.mediaItem.value?.artist, 'My Novel');

    final state = handler.playbackState.value;
    expect(state.playing, isTrue);
    expect(state.processingState, AudioProcessingState.ready);
    expect(state.controls, contains(MediaControl.pause));
    expect(state.controls, contains(MediaControl.stop));
    expect(state.androidCompactActionIndices, [0, 1, 2]);
  });

  test('pausing swaps the control to play', () {
    session.setPlaying(true);
    session.setPlaying(false);

    final state = handler.playbackState.value;
    expect(state.playing, isFalse);
    expect(state.processingState, AudioProcessingState.ready);
    expect(state.controls, contains(MediaControl.play));
  });

  test('hide reports idle and clears the media item', () {
    session.setChapterTitle('Chapter 1');
    session.setPlaying(true);
    session.hide();

    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
    expect(handler.mediaItem.value, isNull);
  });

  test('commands from the handler reach the delegate', () async {
    final delegate = _FakeDelegate();
    session.setDelegate(delegate);

    await handler.play();
    await handler.pause();
    await handler.skipToNext();
    await handler.skipToPrevious();
    await handler.stop();

    expect(delegate.play, 1);
    expect(delegate.pause, 1);
    expect(delegate.next, 1);
    expect(delegate.previous, 1);
    expect(delegate.stop, 1);
  });

  test('stop without a delegate falls back to idle state', () async {
    session.setPlaying(true);

    await handler.stop();

    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
  });

  test('a null delegate drops commands without throwing', () async {
    session.setDelegate(null);

    await handler.play();
    await handler.pause();
    await handler.skipToNext();
    await handler.skipToPrevious();
    await handler.stop();
  });
}
