import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/scraper/data/services/series_details_extractor.dart';

void main() {
  test('a chapter page names the series and offers its cover', () {
    const html = '''
<html><head>
  <meta property="og:site_name" content="Manga18fx">
  <meta property="og:title" content="Space Cheon-ma 3077 - Chapter 108 - Manga18fx">
  <meta property="og:image" content="https://manga18fx.com/webtoon/space-cheon-ma-3077-5092.jpg">
</head><body>
  <h1>Space Cheon-ma 3077 Chapter 108</h1>
</body></html>
''';

    final details = extractSeriesDetails(
      html,
      Uri.parse('https://manga18fx.com/manga/space-cheon-ma-3077/chapter-108'),
    );

    expect(details.title, 'Space Cheon-ma 3077');
    expect(
      details.coverUrl,
      'https://manga18fx.com/webtoon/space-cheon-ma-3077-5092.jpg',
    );
  });

  test('a page that only knows its chapter still names the series', () {
    const html = '''
<html><head>
  <meta property="og:site_name" content="Example">
  <title>Grid Demo - Chapter 12 - Example</title>
</head><body></body></html>
''';

    final details = extractSeriesDetails(
      html,
      Uri.parse('https://example.com/manga/grid-demo/chapter-12'),
    );

    expect(details.title, 'Grid Demo');
    expect(details.coverUrl, isNull);
  });

  test('a page with nothing to say falls back to its address', () {
    final details = extractSeriesDetails(
      '<html><body></body></html>',
      Uri.parse('https://example.com/manga/grid-demo'),
    );

    expect(details.title, 'Grid Demo');
    expect(details.coverUrl, isNull);
  });

  test('a relative cover is resolved against the page', () {
    const html = '''
<html><head>
  <meta property="og:image" content="/covers/demo.jpg">
</head><body></body></html>
''';

    final details = extractSeriesDetails(
      html,
      Uri.parse('https://example.com/manga/demo/chapter-1'),
    );

    expect(details.coverUrl, 'https://example.com/covers/demo.jpg');
  });
}
