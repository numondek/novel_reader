import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/network/dio_client.dart';
import 'package:novel_reader/features/scraper/data/services/chapter_link_finder.dart';
import 'package:novel_reader/features/scraper/data/services/comix_novel_adapter.dart';

const _readShell = '''
<html><head><title>I Married the Dragon I Killed - Ch. 1</title></head>
<body>
<div id="app-root"></div>
<script type="application/json" id="initial-data">
{"page":"read","queries":[],"routes":{},
 "read":{"mangaId":119297,"mangaHid":"50xvk","chapterId":10839967,
         "chapterNumber":1}}
</script>
</body></html>
''';

const _seriesShell = '''
<html><head><title>I Married the Dragon I Killed</title></head>
<body>
<div id="app-root"></div>
<script type="application/json" id="initial-data">
{"page":"manga","queries":[],"routes":{},
 "manga":{"hid":"50xvk","id":119297}}
</script>
</body></html>
''';

const _chapterUrl =
    'https://comix.to/title/50xvk-i-married-the-dragon-i-killed'
    '/10839967-chapter-1';
const _seriesUrl = 'https://comix.to/title/50xvk-i-married-the-dragon-i-killed';

void main() {
  final chapterUrl = Uri.parse(_chapterUrl);
  final seriesUrl = Uri.parse(_seriesUrl);

  test('the pictures of a chapter come from its API entry', () async {
    final adapter = ComixAdapter();
    Uri? requested;

    final refined = await adapter.refine(
      html: _readShell,
      url: chapterUrl,
      load: (uri) async {
        requested = uri;
        return '{"id":10839967,"number":1,'
            '"pages":{'
            '"baseUrl":"https://cdn.comix.to/img",'
            '"items":[{'
            '"url":"/page-1.jpg","width":800,"height":1200},'
            '{"url":"/page-2.jpg","width":800,"height":1200},'
            '{"url":"/page-3.jpg","width":800,"height":1200}'
            ']},"prev":null,"next":null}';
      },
    );

    expect(requested.toString(), 'https://comix.to/api/v1/chapters/10839967');

    final chapter = await adapter.extract(html: refined, url: chapterUrl);

    expect(chapter.imageUrls, [
      'https://cdn.comix.to/img/page-1.jpg',
      'https://cdn.comix.to/img/page-2.jpg',
      'https://cdn.comix.to/img/page-3.jpg',
    ]);
    expect(chapter.title, 'I Married the Dragon I Killed - Ch. 1');
    expect(chapter.nextChapterUrl, isNull);
    expect(chapter.previousChapterUrl, isNull);
  });

  test('the neighbours the API names become the reader links', () async {
    final adapter = ComixAdapter();

    final refined = await adapter.refine(
      html: _readShell,
      url: chapterUrl,
      load:
          (uri) async =>
              '{"id":10839967,'
              '"pages":{"baseUrl":"","items":[{"url":"https://img/x1.jpg"}]},'
              '"prev":{"id":10839966,"url":"/title/50xvk-i-married-the-dragon-i-killed/10839966-chapter-0"},'
              '"next":{"id":10839968,"url":"/title/50xvk-i-married-the-dragon-i-killed/10839968-chapter-2"}}',
    );

    final chapter = await adapter.extract(html: refined, url: chapterUrl);

    expect(chapter.previousChapterUrl, '$_seriesUrl/10839966-chapter-0');
    expect(chapter.nextChapterUrl, '$_seriesUrl/10839968-chapter-2');
  });

  test('a chapter without pictures fails with a readable error', () async {
    final adapter = ComixAdapter();

    expect(
      adapter.refine(
        html: _readShell,
        url: chapterUrl,
        load:
            (uri) async => '{"id":10839967,"pages":{"baseUrl":"","items":[]}}',
      ),
      throwsA(isA<PageFetchException>()),
    );
  });

  test('the chapter list is assembled from the API, page by page', () async {
    final adapter = ComixAdapter();
    final requested = <String>[];

    final listing = await adapter.listingHtml(
      html: _seriesShell,
      url: seriesUrl,
      load: (uri) async {
        requested.add(uri.toString());

        if (uri.query.contains('page=1')) {
          return '{"items":['
              '{"id":10839967,"number":1,"name":"First Blood",'
              '"url":"/title/50xvk-i-married-the-dragon-i-killed/10839967-chapter-1"},'
              '{"id":10839968,"number":2,"name":"Second Blood",'
              '"url":"/title/50xvk-i-married-the-dragon-i-killed/10839968-chapter-2"}'
              '],"meta":{"page":1,"lastPage":2}}';
        }

        return '{"items":['
            '{"id":10839969,"number":3,"name":"Third Blood",'
            '"url":"/title/50xvk-i-married-the-dragon-i-killed/10839969-chapter-3"},'
            '{"id":10839970,"number":4,"name":null}'
            '],"meta":{"page":2,"lastPage":2}}';
      },
    );

    expect(requested, [
      'https://comix.to/api/v1/manga/50xvk/chapters?page=1&limit=100',
      'https://comix.to/api/v1/manga/50xvk/chapters?page=2&limit=100',
    ]);

    final links = findChapterLinks(listing, seriesUrl);

    expect(links.map((link) => link.url), [
      '$_seriesUrl/10839967-chapter-1',
      '$_seriesUrl/10839968-chapter-2',
      '$_seriesUrl/10839969-chapter-3',
      '$_seriesUrl/10839970-chapter-4',
    ]);
    expect(links.first.title, 'Chapter 1 - First Blood');
    expect(links.last.title, 'Chapter 4');
  });

  test('a chapter page on its own lists the series too', () async {
    final adapter = ComixAdapter();
    final requested = <String>[];

    final listing = await adapter.listingHtml(
      html: _readShell,
      url: chapterUrl,
      load: (uri) async {
        requested.add(uri.toString());
        return '{"items":['
            '{"id":10839967,"number":1,"name":null,'
            '"url":"/title/50xvk-i-married-the-dragon-i-killed/10839967-chapter-1"}'
            '],"meta":{"page":1,"lastPage":1}}';
      },
    );

    expect(requested, [
      'https://comix.to/api/v1/manga/50xvk/chapters?page=1&limit=100',
    ]);

    final links = findChapterLinks(listing, seriesUrl);
    expect(links.single.url, '$_seriesUrl/10839967-chapter-1');
  });

  test('the page script asks the site own client for the answer', () {
    final adapter = ComixAdapter();

    final script = adapter.inPageApiScript(
      Uri.parse('https://comix.to/api/v1/chapters/10839967?page=2&limit=100'),
    );

    expect(script, contains('performance.getEntriesByType'));
    expect(script, contains('import(moduleUrl)'));
    expect(script, contains('app.T.get'));
    // The token covers the path alone: the query must not be baked
    // into the URL the client signs.
    expect(script, contains('target.searchParams'));
    expect(script, contains('replace(/^\\/api\\/v1/, \'\')'));
    expect(script, contains('JSON.stringify(data)'));
  });

  test('the adapter owns exactly the comix.to host', () {
    final adapter = ComixAdapter();

    expect(adapter.canHandle(chapterUrl), isTrue);
    expect(adapter.canHandle(Uri.parse('https://comix.to/')), isTrue);
    expect(adapter.canHandle(Uri.parse('https://www.comix.to/x')), isFalse);
    expect(adapter.canHandle(Uri.parse('https://example.com/x')), isFalse);
  });
}
