import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/scraper/data/services/czbooks_novel_adapter.dart';

void main() {
  test(
    'czbooks adapter extracts br-separated chapter content',
    () async {
      final html = File(
        'test/fixtures/czbooks_chapter.html',
      ).readAsStringSync();

      const adapter = CzbooksAdapter();
      final url = Uri.parse(
        'https://czbooks.net/n/s6pcm6/ucp0ldl2?chapterNumber=4681',
      );

      final chapter = await adapter.extract(
        html: html,
        url: url,
      );

      expect(chapter.paragraphs, isNotEmpty);
      expect(chapter.paragraphs.length, greaterThan(10));

      expect(chapter.title, contains('第4682章'));
      expect(chapter.title, isNot(contains('小說狂人')));
      expect(chapter.novelTitle, '開局簽到荒古聖體');

      expect(
        chapter.nextChapterUrl,
        'https://czbooks.net/n/s6pcm6/ucp02269?chapterNumber=4682',
      );
      expect(
        chapter.previousChapterUrl,
        'https://czbooks.net/n/s6pcm6/ucp0l0kg?chapterNumber=4680',
      );
    },
  );
}
