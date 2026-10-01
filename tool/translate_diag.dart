// ignore_for_file: avoid_print

import 'package:novel_reader/features/translation/data/services/google_translate_service.dart';

Future<void> main() async {
  final service = GoogleTranslateService();

  final paragraph =
      '林尘睁开双眼，发现自己置身于一片陌生的山林之中，四周古木参天，灵气氤氲。';
  final paragraphs = List<String>.generate(
    40,
    (i) => '$paragraph第${i + 1}段，他深吸一口气，感受着体内涌动的力量，缓缓站起身来。',
  );

  print('paragraphs=${paragraphs.length} '
      'chars=${paragraphs.fold<int>(0, (a, b) => a + b.length)}');

  final sw = Stopwatch()..start();
  final result = await service.translateParagraphs(
    paragraphs,
    targetLanguage: 'en',
  );
  sw.stop();

  print('translated=${result.length} in ${sw.elapsedMilliseconds}ms');
  print('first: ${result.first}');
  print('last: ${result.last}');

  final ok = result.length == paragraphs.length &&
      result.every((r) => r.trim().isNotEmpty);
  print(ok ? 'SUCCESS' : 'FAILED: line count mismatch');
}
