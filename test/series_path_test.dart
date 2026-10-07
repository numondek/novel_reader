import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/scraper/data/services/chapter_link_finder.dart';
import 'package:novel_reader/features/scraper/data/services/series_path.dart';

void main() {
  test('a chapter page and its series page share one key', () {
    final chapter = Uri.parse(
      'https://manga18fx.com/manga/space-cheon-ma-3077/chapter-108',
    );
    final series = Uri.parse('https://manga18fx.com/manga/space-cheon-ma-3077');

    expect(seriesPathOf(chapter), '/manga/space-cheon-ma-3077');
    expect(seriesPathOf(series), '/manga/space-cheon-ma-3077');

    expect(manhwaNovelKey(chapter), manhwaNovelKey(series));
    expect(
      manhwaNovelKey(chapter),
      'manhwa:manga18fx.com/manga/space-cheon-ma-3077',
    );
  });

  test('a trailing slash does not change the key', () {
    expect(
      manhwaNovelKey(Uri.parse('https://example.com/manhwa/demo/')),
      'manhwa:example.com/manhwa/demo',
    );
  });

  test('a numeric chapter page still keys to its series', () {
    expect(
      manhwaNovelKey(Uri.parse('https://example.com/manhwa/demo/45')),
      'manhwa:example.com/manhwa/demo',
    );
  });

  test('the chapters decide the series when they are known', () {
    const links = [
      ChapterLink(
        title: 'Chapter 1',
        url: 'https://x.com/manga/demo/chapter-1',
      ),
      ChapterLink(
        title: 'Chapter 2',
        url: 'https://x.com/manga/demo/chapter-2',
      ),
    ];

    expect(
      manhwaNovelKey(Uri.parse('https://x.com/latest'), links: links),
      'manhwa:x.com/manga/demo',
    );
  });

  test('series sharing one reader folder keep their own key', () {
    const pickMeUp = [
      ChapterLink(
        title: 'Chapter: 161-eng-li',
        url: 'https://www.mgeko.cc/reader/en/pick-me-up-chapter-161-eng-li/',
      ),
      ChapterLink(
        title: 'Chapter: 160-eng-li',
        url: 'https://www.mgeko.cc/reader/en/pick-me-up-chapter-160-eng-li/',
      ),
    ];
    const otherSeries = [
      ChapterLink(
        title: 'Chapter: 50-eng-li',
        url: 'https://www.mgeko.cc/reader/en/solo-leveling-chapter-50-eng-li/',
      ),
    ];

    final chapter = Uri.parse(
      'https://www.mgeko.cc/reader/en/pick-me-up-chapter-161-eng-li/',
    );

    // The key the reader records by hand is the key the shelf
    // derives from the chapter list.
    expect(
      manhwaNovelKey(chapter, links: pickMeUp),
      'manhwa:www.mgeko.cc/reader/en/pick-me-up',
    );
    expect(manhwaNovelKey(chapter), manhwaNovelKey(chapter, links: pickMeUp));

    // Another series of the same site lands somewhere else.
    expect(
      manhwaNovelKey(
        Uri.parse('https://www.mgeko.cc/manga/solo-leveling/'),
        links: otherSeries,
      ),
      'manhwa:www.mgeko.cc/reader/en/solo-leveling',
    );
  });

  test('a chapter file named without a marker keys to its folder', () {
    const links = [
      ChapterLink(title: 'Extra', url: 'https://x.com/manhwa/demo/special-2'),
    ];

    expect(
      manhwaNovelKey(Uri.parse('https://x.com/latest'), links: links),
      'manhwa:x.com/manhwa/demo',
    );
  });

  test('an asurascans chapter keys to the series behind it', () {
    final chapter = Uri.parse(
      'https://asurascans.com/comics/myst-might-mayhem-bd5bdaf8/chapter/116',
    );
    final series = Uri.parse(
      'https://asurascans.com/comics/myst-might-mayhem-bd5bdaf8',
    );

    expect(seriesPathOf(chapter), '/comics/myst-might-mayhem-bd5bdaf8');
    expect(seriesPathOf(series), '/comics/myst-might-mayhem-bd5bdaf8');

    expect(manhwaNovelKey(chapter), manhwaNovelKey(series));
    expect(
      manhwaNovelKey(chapter),
      'manhwa:asurascans.com/comics/myst-might-mayhem-bd5bdaf8',
    );
  });

  test('the chapter list and the chapter page agree on the series', () {
    const links = [
      ChapterLink(
        title: 'Chapter 116',
        url:
            'https://asurascans.com/comics/myst-might-mayhem-bd5bdaf8/chapter/116',
      ),
      ChapterLink(
        title: 'Chapter 115',
        url:
            'https://asurascans.com/comics/myst-might-mayhem-bd5bdaf8/chapter/115',
      ),
    ];

    expect(seriesPathFrom(links), '/comics/myst-might-mayhem-bd5bdaf8');
    expect(
      manhwaNovelKey(
        Uri.parse(
          'https://asurascans.com/comics/myst-might-mayhem-bd5bdaf8/chapter/116',
        ),
        links: links,
      ),
      'manhwa:asurascans.com/comics/myst-might-mayhem-bd5bdaf8',
    );
  });

  test('only one slash reaches the chapter number', () {
    expect(
      seriesPathOf(Uri.parse('https://example.com/comics/chapter-5/chapter-1')),
      '/comics/chapter-5',
    );
  });

  test('a fanmtl chapter file keys to the series file behind it', () {
    final chapter = Uri.parse(
      'https://www.fanmtl.com/novel/everlasting-dragon-emperor_2.html',
    );
    final series = Uri.parse(
      'https://www.fanmtl.com/novel/everlasting-dragon-emperor.html',
    );

    expect(seriesPathOf(chapter), '/novel/everlasting-dragon-emperor.html');
    expect(seriesPathOf(series), '/novel/everlasting-dragon-emperor.html');

    expect(manhwaNovelKey(chapter), manhwaNovelKey(series));
    expect(
      manhwaNovelKey(chapter),
      'manhwa:www.fanmtl.com/novel/everlasting-dragon-emperor.html',
    );
  });
}
