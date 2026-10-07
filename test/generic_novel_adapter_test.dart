import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/scraper/data/services/generic_novel_adapter.dart';
import 'package:novel_reader/features/scraper/domain/models/extracted_chapter.dart';

Future<ExtractedChapter> _extract(
  String html, {
  String url = 'https://example.com/manhwa/demo/chapter-1',
}) {
  return GenericNovelAdapter().extract(html: html, url: Uri.parse(url));
}

void main() {
  test('a manhwa chapter extracts its pictures in reading order', () async {
    const html = '''
<html><head><title>Demo</title></head><body>
  <div class="reading-content">
    <img data-src="/img/1.jpg" src="data:image/gif;base64,blank" width="800">
    <img src="https://cdn.example.com/2.png" width="800">
    <img srcset="/img/3-small.jpg 480w, /img/3-large.jpg 1024w" width="800">
  </div>
</body></html>
''';

    final chapter = await _extract(html);

    expect(chapter.hasImages, isTrue);
    expect(chapter.imageUrls, [
      'https://example.com/img/1.jpg',
      'https://cdn.example.com/2.png',
      'https://example.com/img/3-large.jpg',
    ]);
  });

  test('a text chapter with an illustration stays in text mode', () async {
    const prose =
        'The night was long and the road endless, but she kept walking '
        'because there was nothing left behind her to hold on to, and '
        'the promise she made waited at the end of the valley.';

    final html = '''
<html><body>
  <article>
    <img src="/illustration.jpg" width="600">
    <p>$prose</p>
    <p>$prose</p>
  </article>
</body></html>
''';

    final chapter = await _extract(html);

    expect(chapter.imageUrls, isEmpty);
    expect(chapter.hasImages, isFalse);
    expect(chapter.paragraphs, hasLength(2));
  });

  test('a page without content throws', () async {
    const html = '''
<html><body>
  <img src="/logo.png">
</body></html>
''';

    expect(
      () => _extract(html),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('Could not find chapter content on this page.'),
        ),
      ),
    );
  });

  test('tiny and decorated images are not chapter pictures', () async {
    const html = '''
<html><body>
  <div id="chapter-content">
    <img src="/icons/star.svg" width="16">
    <img src="/banner-ad.jpg" width="728">
    <img src="/avatar.png" width="120">
    <img src="/panel-1.jpg" width="800">
    <img src="/panel-2.jpg" width="800">
  </div>
</body></html>
''';

    final chapter = await _extract(html);

    expect(chapter.imageUrls, [
      'https://example.com/panel-1.jpg',
      'https://example.com/panel-2.jpg',
    ]);
  });

  test(
    'a reader page keeps its strip and drops the hidden search text',
    () async {
      const html = '''
<html><body>
  <article style="display: none;">
    <p>Search junk</p>
  </article>
  <div id="chapter-reader">
    <img src="https://cdn.example.com/1.jpg">
    <img src="https://cdn.example.com/2.jpg">
    <img src="https://cdn.example.com/3.jpg">
  </div>
</body></html>
''';

      final chapter = await _extract(html);

      expect(chapter.imageUrls, hasLength(3));
      expect(chapter.paragraphs, isEmpty);
    },
  );

  test(
    'a bare page of pictures with no container still reads as a strip',
    () async {
      const html = '''
<html><body>
  <p>A short caption.</p>
  <div>
    <img src="/p-1.jpg">
    <img src="/p-2.jpg">
    <img src="/p-3.jpg">
  </div>
</body></html>
''';

      final chapter = await _extract(html);

      expect(chapter.imageUrls, [
        'https://example.com/p-1.jpg',
        'https://example.com/p-2.jpg',
        'https://example.com/p-3.jpg',
      ]);
    },
  );
}
