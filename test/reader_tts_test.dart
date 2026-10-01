import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/reader/domain/services/text_to_speech.dart';
import 'package:novel_reader/features/reader/presentation/providers/reader_tts_controller.dart';

class _FakeTts implements TextToSpeech {
  String? language;
  double? rate;
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
}
