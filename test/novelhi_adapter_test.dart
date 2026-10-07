import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/scraper/data/services/novelhi_novel_adapter.dart';

const _shell = '''
<html><head><title>Chapter 1526 - I Am Supreme</title></head><body>
<h1>Chapter 1526</h1>
<input type="hidden" id="chapterContentPath"
       value="/novel/action/i-am-supreme/1526/content">
<input type="hidden" id="chapterContentToken"
       value="9946ab75fe8746968d29fdc1edcddf96">
<div id="showReading">
  <div class="orderBox"><h3>Order the books</h3></div>
</div>
<a class="ico_pagePrev" href="https://novelhi.com/novel/action/i-am-supreme/1525"
   title="Prev">&lsaquo;</a>
<a class="ico_pageNext" href="https://novelhi.com/novel/action/i-am-supreme/1527"
   title="Next">&rsaquo;</a>
<a class="prev" href="https://novelhi.com/novel/action/i-am-supreme/1525">Prev</a>
<a class="next" href="https://novelhi.com/novel/action/i-am-supreme/1527">Next</a>
</body></html>
''';

const _chapterUrl = 'https://novelhi.com/novel/action/i-am-supreme/1526';

String _contentJson(String content, {required bool obfuscated}) {
  return '{"code":"200","msg":"SUCCESS","data":{'
      '"fontClass":"novelhi-chapter-obf",'
      '"fontFaceCss":"@font-face{font-family:\'NovelHiChapterObf\';}",'
      '"content":${_jsonString(content)},'
      '"fontObfuscation":$obfuscated'
      '}}';
}

String _jsonString(String value) {
  final escaped = value
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n');
  return '"$escaped"';
}

void main() {
  final url = Uri.parse(_chapterUrl);

  test(
    'the obfuscated content is fetched, decoded and made into paragraphs',
    () async {
      final adapter = NovelhiAdapter();
      Uri? requested;

      final refined = await adapter.refine(
        html: _shell,
        url: url,
        load: (uri) async {
          requested = uri;

          // Exactly what the site ships: rot13 text in <sent> runs.
          return _contentJson(
            '<sent id=0>Vg jnf vapbzcerurafvoyr naq haoryvrinoyr.</sent>'
            '<br><br>'
            '<sent id=1>Ur erznvarq fvyrag.</sent>'
            '<br><br>'
            '<ins class="adsbygoogle">ad</ins>',
            obfuscated: true,
          );
        },
      );

      expect(
        requested.toString(),
        'https://novelhi.com/novel/action/i-am-supreme/1526/content'
        '?token=9946ab75fe8746968d29fdc1edcddf96',
      );
      expect(refined, isNot(contains('vapbzcerurafvoyr')));
      expect(refined, isNot(contains('orderBox')));

      final chapter = await adapter.extract(html: refined, url: url);

    expect(chapter.paragraphs, [
      'It was incomprehensible and unbelievable.',
      'He remained silent.',
    ]);
      expect(chapter.title, 'Chapter 1526');
      expect(
        chapter.nextChapterUrl,
        'https://novelhi.com/novel/action/i-am-supreme/1527',
      );
      expect(
        chapter.previousChapterUrl,
        'https://novelhi.com/novel/action/i-am-supreme/1525',
      );
    },
  );

  test('plain paragraphs pass through without decoding', () async {
    final adapter = NovelhiAdapter();

    final refined = await adapter.refine(
      html: _shell,
      url: url,
      load: (uri) async {
        return _contentJson(
          '<p>First paragraph.</p><p>Second paragraph.</p>',
          obfuscated: false,
        );
      },
    );

    final chapter = await adapter.extract(html: refined, url: url);

    expect(chapter.paragraphs, ['First paragraph.', 'Second paragraph.']);
  });

  test('a page without the endpoint keeps its own markup', () async {
    final adapter = NovelhiAdapter();
    const gated = '<html><body><h1>Log in</h1></body></html>';

    final refined = await adapter.refine(
      html: gated,
      url: url,
      load: (uri) async => fail('no second request expected'),
    );

    expect(refined, gated);
  });

  test('the content endpoint asks for the page-style headers', () {
    final adapter = NovelhiAdapter();

    expect(adapter.canHandle(url), isTrue);
    expect(adapter.canHandle(Uri.parse('https://example.com/x')), isFalse);

    expect(adapter.requestHeaders(url), isEmpty);

    final headers = adapter.requestHeaders(
      url.resolve('/novel/action/i-am-supreme/1526/content'),
    );
    expect(headers['X-Requested-With'], 'XMLHttpRequest');
    expect(headers['Referer'], 'https://novelhi.com/');
  });
}
