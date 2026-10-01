import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as parser;
import 'package:novel_reader/features/scraper/data/services/novel_title_extractor.dart';

void main() {
  test('reads og:novel meta tags first', () {
    final document = parser.parse('''
<html><head>
<meta property="og:novel:novel_name" content="Martial Peak">
<meta property="og:novel:chapter_name" content="Chapter 1">
</head><body></body></html>
''');

    expect(extractNovelTitle(document), 'Martial Peak');
  });

  test('reads the novel name from a 《...》 heading', () {
    final document = parser.parse('''
<html><body>
<div class="name">《My Cultivation Book》第12章 The breakthrough</div>
</body></html>
''');

    expect(extractNovelTitle(document), 'My Cultivation Book');
  });

  test('reads the last breadcrumb link, stripping 《目錄》', () {
    final document = parser.parse('''
<html><body>
<div class="position">
  <a href="/">Home</a> &gt;
  <a href="/c/fantasy">Fantasy</a> &gt;
  <a href="/n/abc">Deep Legend 《目錄》</a>
</div>
</body></html>
''');

    expect(extractNovelTitle(document), 'Deep Legend');
  });

  test('returns null when the page has no novel name markers', () {
    final document = parser.parse('''
<html><head><title>Chapter 3 | Some Site</title></head>
<body><h1>Chapter 3</h1></body></html>
''');

    expect(extractNovelTitle(document), isNull);
  });
}
