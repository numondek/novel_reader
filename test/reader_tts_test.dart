import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/reader/domain/services/media_session.dart';
import 'package:novel_reader/features/reader/domain/services/playback_interruptions.dart';
import 'package:novel_reader/features/reader/domain/services/text_to_speech.dart';
import 'package:novel_reader/features/reader/presentation/providers/reader_tts_controller.dart';
import 'package:novel_reader/features/settings/presentation/providers/settings_provider.dart';

class _FakeTts implements TextToSpeech {
  String? language;
  double? rate;
  String? voiceName;
  String? voiceLocale;
  int stopCalls = 0;

  final List<String> spoken = <String>[];

  void Function()? completion;
  void Function()? cancel;
  void Function(dynamic message)? error;

  @override
  Future<void> setLanguage(String language) async {
    this.language = language;
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    this.rate = rate;
  }

  @override
  Future<void> setVoice(String name, String locale) async {
    voiceName = name;
    voiceLocale = locale;
  }

  @override
  Future<List<TtsVoice>> getVoices() async => const [];

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  void onCompletion(void Function() handler) {
    completion = handler;
  }

  @override
  void onCancel(void Function() handler) {
    cancel = handler;
  }

  @override
  void onError(void Function(dynamic message) handler) {
    error = handler;
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

class _FakeMediaSession implements MediaSession {
  MediaSessionDelegate? delegate;
  String? title;
  String? subtitle;
  bool? playing;
  int hideCalls = 0;

  @override
  void setDelegate(MediaSessionDelegate? delegate) {
    this.delegate = delegate;
  }

  @override
  void setChapterTitle(String title, {String? subtitle}) {
    this.title = title;
    this.subtitle = subtitle;
  }

  @override
  void setPlaying(bool playing) {
    this.playing = playing;
  }

  @override
  void hide() {
    hideCalls += 1;
  }
}

class _FakePlaybackInterruptions implements PlaybackInterruptions {
  PlaybackInterruptionsDelegate? delegate;
  final List<bool> activeCalls = <bool>[];

  @override
  void setDelegate(PlaybackInterruptionsDelegate? delegate) {
    this.delegate = delegate;
  }

  @override
  Future<void> setActive(bool active) async {
    activeCalls.add(active);
  }
}

void main() {
  test('speaks CJK text with the Chinese language', () async {
    final fake = _FakeTts();
    final controller = ReaderTtsController(tts: fake);

    await controller.play(['你好世界', '第二段']);

    expect(fake.language, 'zh-CN');
    expect(fake.rate, ReaderTtsController.speechRate);
    expect(fake.spoken, ['你好世界']);
    expect(controller.state.isPlaying, isTrue);
    expect(controller.state.currentIndex, 0);
  });

  test('speaks English text with the English language', () async {
    final fake = _FakeTts();
    final controller = ReaderTtsController(tts: fake);

    await controller.play(['Hello world']);

    expect(fake.language, 'en-US');
  });

  test('completion advances paragraph by paragraph', () async {
    final fake = _FakeTts();
    final controller = ReaderTtsController(tts: fake);

    await controller.play(['一', '二', '三']);

    fake.completion!();
    await flush();
    expect(controller.state.currentIndex, 1);
    expect(fake.spoken, ['一', '二']);

    fake.completion!();
    await flush();
    expect(controller.state.currentIndex, 2);
    expect(fake.spoken, ['一', '二', '三']);
  });

  test('stops after the last paragraph', () async {
    final fake = _FakeTts();
    final controller = ReaderTtsController(tts: fake);

    await controller.play(['only']);
    fake.completion!();
    await flush();

    expect(controller.state.isPlaying, isFalse);
    expect(controller.state.isPaused, isFalse);
    expect(controller.state.currentIndex, 0);
    expect(fake.stopCalls, greaterThanOrEqualTo(1));
  });

  test('blank paragraphs are skipped instead of spoken', () async {
    final fake = _FakeTts();
    final controller = ReaderTtsController(tts: fake);

    await controller.play(['Hello', '   ', 'World']);

    expect(fake.spoken, ['Hello']);

    fake.completion!();
    await flush();

    expect(controller.state.currentIndex, 2);
    expect(fake.spoken, ['Hello', 'World']);
  });

  test('a chapter of blank paragraphs never starts speaking', () async {
    final fake = _FakeTts();
    final controller = ReaderTtsController(tts: fake);

    await controller.play(['', '   ']);

    expect(fake.spoken, isEmpty);
    expect(controller.state.isPlaying, isFalse);
  });

  test('a blank first paragraph is skipped on play', () async {
    final fake = _FakeTts();
    final controller = ReaderTtsController(tts: fake);

    await controller.play(['', 'Hi']);

    expect(fake.spoken, ['Hi']);
    expect(controller.state.currentIndex, 1);
  });

  test('an oversized paragraph is spoken in engine-sized pieces', () async {
    final fake = _FakeTts();
    final controller = ReaderTtsController(tts: fake);

    final piece = 'a' * (ReaderTtsController.maxSpeechChars - 10);
    final text = '$piece $piece $piece';

    await controller.play([text, 'After']);

    expect(fake.spoken, hasLength(1));
    expect(
      fake.spoken.first.length,
      lessThanOrEqualTo(ReaderTtsController.maxSpeechChars),
    );
    expect(controller.state.currentIndex, 0);

    fake.completion!();
    await flush();
    expect(fake.spoken, hasLength(2));
    expect(controller.state.currentIndex, 0);

    fake.completion!();
    await flush();
    expect(fake.spoken, hasLength(3));
    expect(controller.state.currentIndex, 0);

    fake.completion!();
    await flush();
    expect(controller.state.currentIndex, 1);
    expect(fake.spoken.last, 'After');
  });

  test('a raw engine error is shown as a friendly message', () async {
    final fake = _FakeTts();
    final controller = ReaderTtsController(tts: fake);

    await controller.play(['Hello']);
    fake.error!('Error from TextToSpeech ( speak ) --8');
    await flush();

    expect(controller.state.error, contains('Text-to-speech failed'));
    expect(controller.state.isPlaying, isFalse);
  });

  test('pause keeps the index and resume replays it', () async {
    final fake = _FakeTts();
    final controller = ReaderTtsController(tts: fake);

    await controller.play(['一', '二', '三']);
    fake.completion!();
    await flush();
    expect(controller.state.currentIndex, 1);

    await controller.pause();
    expect(controller.state.isPlaying, isFalse);
    expect(controller.state.isPaused, isTrue);
    expect(controller.state.currentIndex, 1);
    expect(fake.stopCalls, greaterThanOrEqualTo(1));

    await controller.resume();
    expect(controller.state.isPlaying, isTrue);
    expect(controller.state.currentIndex, 1);
    expect(fake.spoken.last, '二');
  });

  test('seek speaks the requested paragraph', () async {
    final fake = _FakeTts();
    final controller = ReaderTtsController(tts: fake);

    await controller.play(['一', '二', '三']);
    await controller.seek(2);

    expect(controller.state.currentIndex, 2);
    expect(fake.spoken, ['一', '三']);
  });

  test('errors surface as state and stop playback', () async {
    final fake = _FakeTts();
    final controller = ReaderTtsController(tts: fake);

    await controller.play(['一']);
    fake.error!('Engine not available');
    await flush();

    expect(controller.state.error, contains('Engine not available'));
    expect(controller.state.isPlaying, isFalse);
    expect(controller.state.isPaused, isFalse);
  });

  test('fires onFinished after the last paragraph', () async {
    final fake = _FakeTts();
    final controller = ReaderTtsController(tts: fake);

    var finished = false;
    controller.onFinished = () => finished = true;

    await controller.play(['only']);
    fake.completion!();
    await flush();

    expect(finished, isTrue);
  });

  test('ignores completion after cancel', () async {
    final fake = _FakeTts();
    final controller = ReaderTtsController(tts: fake);

    await controller.play(['一', '二']);
    fake.cancel!();
    await flush();

    expect(controller.state.isPlaying, isFalse);
    expect(controller.state.isPaused, isTrue);
    expect(controller.state.currentIndex, 0);
  });

  test('applies the configured speech rate', () async {
    final fake = _FakeTts();
    final controller = ReaderTtsController(
      tts: fake,
      settings: () => const AppSettings(speechRate: 0.8),
    );

    await controller.play(['Hello world']);

    expect(fake.rate, 0.8);
  });

  test('applies a selected voice when it matches the language', () async {
    final fake = _FakeTts();
    final controller = ReaderTtsController(
      tts: fake,
      settings:
          () => const AppSettings(voiceName: 'Alice', voiceLocale: 'en-US'),
    );

    await controller.play(['Hello world']);

    expect(fake.language, 'en-US');
    expect(fake.voiceName, 'Alice');
    expect(fake.voiceLocale, 'en-US');
  });

  test('skips the selected voice for a different language', () async {
    final fake = _FakeTts();
    final controller = ReaderTtsController(
      tts: fake,
      settings:
          () => const AppSettings(voiceName: 'Alice', voiceLocale: 'en-US'),
    );

    await controller.play(['你好世界']);

    expect(fake.language, 'zh-CN');
    expect(fake.voiceName, isNull);
  });

  test(
    'completion re-applies rate before speaking the next paragraph',
    () async {
      final fake = _FakeTts();
      final controller = ReaderTtsController(
        tts: fake,
        settings: () => const AppSettings(speechRate: 0.3),
      );

      await controller.play(['one', 'two']);
      fake.completion!();
      await flush();

      expect(fake.rate, 0.3);
      expect(fake.spoken, ['one', 'two']);
    },
  );

  test('play publishes the chapter title and playing state', () async {
    final fake = _FakeTts();
    final session = _FakeMediaSession();
    final controller = ReaderTtsController(tts: fake, mediaSession: session);

    await controller.play(['Hello'], title: 'Chapter 1');

    expect(session.title, 'Chapter 1');
    expect(session.playing, isTrue);
    expect(session.hideCalls, 0);
  });

  test('pause reports the session as paused without hiding it', () async {
    final fake = _FakeTts();
    final session = _FakeMediaSession();
    final controller = ReaderTtsController(tts: fake, mediaSession: session);

    await controller.play(['Hello'], title: 'Chapter 1');
    await controller.pause();

    expect(session.playing, isFalse);
    expect(session.hideCalls, 0);
  });

  test('stop hides the media session', () async {
    final fake = _FakeTts();
    final session = _FakeMediaSession();
    final controller = ReaderTtsController(tts: fake, mediaSession: session);

    await controller.play(['Hello'], title: 'Chapter 1');
    await controller.stopAll();

    expect(session.hideCalls, 1);
    expect(controller.state.isPlaying, isFalse);
  });

  test('an engine error hides the media session', () async {
    final fake = _FakeTts();
    final session = _FakeMediaSession();
    final controller = ReaderTtsController(tts: fake, mediaSession: session);

    await controller.play(['Hello'], title: 'Chapter 1');
    fake.error!('Engine not available');
    await flush();

    expect(session.hideCalls, 1);
  });

  test('a system play command resumes paused narration', () async {
    final fake = _FakeTts();
    final session = _FakeMediaSession();
    final controller = ReaderTtsController(tts: fake, mediaSession: session);

    await controller.play(['一', '二'], title: '第一章');
    await controller.pause();

    await session.delegate!.onPlay();

    expect(controller.state.isPlaying, isTrue);
    expect(fake.spoken.last, '一');
    expect(session.playing, isTrue);
  });

  test('a system stop command ends narration and hides the session', () async {
    final fake = _FakeTts();
    final session = _FakeMediaSession();
    final controller = ReaderTtsController(tts: fake, mediaSession: session);

    await controller.play(['Hello'], title: 'Chapter 1');

    await session.delegate!.onStop();

    expect(controller.state.isPlaying, isFalse);
    expect(controller.state.isPaused, isFalse);
    expect(session.hideCalls, 1);
  });

  test('a system skip command moves to the next paragraph', () async {
    final fake = _FakeTts();
    final session = _FakeMediaSession();
    final controller = ReaderTtsController(tts: fake, mediaSession: session);

    await controller.play(['一', '二']);

    await session.delegate!.onSkipNext();

    expect(controller.state.currentIndex, 1);
    expect(fake.spoken, ['一', '二']);
  });

  test('disposal releases the media session delegate', () {
    final fake = _FakeTts();
    final session = _FakeMediaSession();

    final container = ProviderContainer(
      overrides: [
        ttsServiceProvider.overrideWithValue(fake),
        mediaSessionProvider.overrideWithValue(session),
      ],
    );

    container.read(readerTtsControllerProvider.notifier);
    expect(session.delegate, isNotNull);

    container.dispose();
    expect(session.delegate, isNull);
  });

  test('another app starting pauses the narration', () async {
    final fake = _FakeTts();
    final interruptions = _FakePlaybackInterruptions();
    final controller = ReaderTtsController(
      tts: fake,
      playbackInterruptions: interruptions,
    );

    await controller.play(['Hello world']);
    interruptions.delegate!.onOtherAudioStarted();
    await flush();

    expect(controller.state.isPlaying, isFalse);
    expect(controller.state.isPaused, isTrue);
    expect(fake.stopCalls, 1);
  });

  test('the other app stopping resumes the narration', () async {
    final fake = _FakeTts();
    final interruptions = _FakePlaybackInterruptions();
    final controller = ReaderTtsController(
      tts: fake,
      playbackInterruptions: interruptions,
    );

    await controller.play(['Hello world']);
    interruptions.delegate!.onOtherAudioStarted();
    await flush();
    interruptions.delegate!.onOtherAudioEnded();
    await flush();

    expect(controller.state.isPlaying, isTrue);
    expect(fake.spoken, ['Hello world', 'Hello world']);
  });

  test('an idle narration is left alone by interruptions', () async {
    final fake = _FakeTts();
    final interruptions = _FakePlaybackInterruptions();
    final controller = ReaderTtsController(
      tts: fake,
      playbackInterruptions: interruptions,
    );

    interruptions.delegate!.onOtherAudioStarted();
    interruptions.delegate!.onOtherAudioEnded();
    await flush();

    expect(controller.state.isPlaying, isFalse);
    expect(controller.state.isPaused, isFalse);
    expect(fake.spoken, isEmpty);
  });

  test(
    'a narration the user paused stays paused when the other app stops',
    () async {
      final fake = _FakeTts();
      final interruptions = _FakePlaybackInterruptions();
      final controller = ReaderTtsController(
        tts: fake,
        playbackInterruptions: interruptions,
      );

      await controller.play(['Hello world']);
      await controller.pause();

      interruptions.delegate!.onOtherAudioStarted();
      interruptions.delegate!.onOtherAudioEnded();
      await flush();

      expect(controller.state.isPlaying, isFalse);
      expect(controller.state.isPaused, isTrue);
      expect(fake.spoken, ['Hello world']);
    },
  );

  test('stopping narration drops the automatic resume', () async {
    final fake = _FakeTts();
    final interruptions = _FakePlaybackInterruptions();
    final controller = ReaderTtsController(
      tts: fake,
      playbackInterruptions: interruptions,
    );

    await controller.play(['Hello world']);
    interruptions.delegate!.onOtherAudioStarted();
    await flush();
    await controller.stopAll();

    interruptions.delegate!.onOtherAudioEnded();
    await flush();

    expect(controller.state.isPlaying, isFalse);
    expect(fake.spoken, ['Hello world']);
  });

  test('audio focus follows playback', () async {
    final fake = _FakeTts();
    final interruptions = _FakePlaybackInterruptions();
    final controller = ReaderTtsController(
      tts: fake,
      playbackInterruptions: interruptions,
    );

    await controller.play(['Hello world']);
    expect(interruptions.activeCalls, [true]);

    await controller.stopAll();
    expect(interruptions.activeCalls, [true, false]);
  });

  test('disposal releases the playback interruptions delegate', () {
    final fake = _FakeTts();
    final interruptions = _FakePlaybackInterruptions();

    final container = ProviderContainer(
      overrides: [
        ttsServiceProvider.overrideWithValue(fake),
        playbackInterruptionsProvider.overrideWithValue(interruptions),
      ],
    );

    container.read(readerTtsControllerProvider.notifier);
    expect(interruptions.delegate, isNotNull);

    container.dispose();
    expect(interruptions.delegate, isNull);
  });
}
