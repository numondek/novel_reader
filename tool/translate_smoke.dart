// CLI smoke test for GoogleTranslateService (Dio path, no Flutter).
// ignore_for_file: avoid_print
import 'package:novel_reader/features/translation/data/services/google_translate_service.dart';

Future<void> main() async {
  final service = GoogleTranslateService();

  final translated = await service.translateParagraphs(
    [
      '十小圣之首，通天妖圣现身',
      '通天妖圣现身，妖庭天命另有其人',
      '第三段，这里还有更多内容',
    ],
    targetLanguage: 'en',
  );

  print('paragraphs: ${translated.length}');
  for (final line in translated) {
    print('- $line');
  }
}
