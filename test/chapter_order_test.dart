import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/scraper/data/services/chapter_link_finder.dart';
import 'package:novel_reader/features/scraper/data/services/chapter_order.dart';

void main() {
  test('reads the chapter number from the title, then the URL', () {
    expect(chapterNumberOf('Chapter 108', 'https://x.com/a/b'), 108);
    expect(chapterNumberOf('10. The duel', 'https://x.com/a/b'), 10);
    expect(chapterNumberOf('The return', 'https://x.com/a/ep-100'), 100);
    expect(chapterNumberOf('Extra', 'https://x.com/a/45'), 45);
    expect(chapterNumberOf('PREV CHAPTER', 'https://x.com/a/chapter-7'), 7);
    expect(chapterNumberOf('Demo', 'https://x.com/manhwa/demo'), isNull);
  });

  test('the series name of a page is not mistaken for a chapter', () {
    const title = 'Space Cheon-ma 3077 Chapter 108';

    expect(chapterNumberOf(title, 'https://x.com/manga/space-3077'), 108);
  });

  test('a row always carries its chapter number', () {
    // A title that spells the number out is left alone.
    expect(
      chapterLabelOf('Chapter 12', 'https://x.com/a/chapter-12'),
      'Chapter 12',
    );
    expect(
      chapterLabelOf('10. The duel', 'https://x.com/a/10'),
      '10. The duel',
    );
    expect(
      chapterLabelOf('第4682章 十小聖之首', 'https://x.com/n/abc'),
      '第4682章 十小聖之首',
    );

    // A title without one takes it from the link.
    expect(
      chapterLabelOf('The duel', 'https://x.com/a/chapter-12'),
      '#12 · The duel',
    );
    expect(
      chapterLabelOf('The return', 'https://x.com/a/ep-100'),
      '#100 · The return',
    );

    // Nothing to show means nothing is invented.
    expect(chapterLabelOf('Bonus', 'https://x.com/a/bonus'), 'Bonus');
    expect(chapterLabelOf('', 'https://x.com/a/chapter-4'), '#4');
    expect(chapterLabelOf('', 'https://x.com/a/bonus'), '');
  });

  test('a reader page always names its chapter number', () {
    const url = 'https://www.mgeko.cc/reader/en/pick-me-up-chapter-161-eng-li/';

    expect(chapterNumberOf('Chapter: 161-eng-li', url), 161);
    expect(chapterLabelOf('Chapter: 161-eng-li', url), 'Chapter: 161-eng-li');
    expect(chapterLabelOf('Pick Me Up', url), '#161 · Pick Me Up');
    expect(chapterLabelOf('', url), '#161');
  });

  test('a reader jump list comes back oldest first', () {
    const links = [
      ChapterLink(
        title: 'Chapter: 160-eng-li',
        url: 'https://www.mgeko.cc/reader/en/pick-me-up-chapter-160-eng-li/',
      ),
      ChapterLink(
        title: 'Chapter: 98a-eng-li',
        url: 'https://www.mgeko.cc/reader/en/pick-me-up-chapter-98a-eng-li/',
      ),
      ChapterLink(
        title: 'Chapter: 161-eng-li',
        url: 'https://www.mgeko.cc/reader/en/pick-me-up-chapter-161-eng-li/',
      ),
    ];

    final ordered = chaptersInReadingOrder(
      links,
      title: (link) => link.title,
      url: (link) => link.url,
    );

    expect(ordered.map((link) => link.title), [
      'Chapter: 98a-eng-li',
      'Chapter: 160-eng-li',
      'Chapter: 161-eng-li',
    ]);
  });

  test('chapters come back oldest first', () {
    const links = [
      ChapterLink(title: 'Chapter 3', url: 'https://x.com/a/chapter-3'),
      ChapterLink(title: 'Chapter 1', url: 'https://x.com/a/chapter-1'),
      ChapterLink(title: 'Chapter 2', url: 'https://x.com/a/chapter-2'),
    ];

    final ordered = chaptersInReadingOrder(
      links,
      title: (link) => link.title,
      url: (link) => link.url,
    );

    expect(ordered.map((link) => link.title), [
      'Chapter 1',
      'Chapter 2',
      'Chapter 3',
    ]);
  });

  test('a list that cannot be ordered is left alone', () {
    const links = [
      ChapterLink(title: 'Extra', url: 'https://x.com/a/bonus'),
      ChapterLink(title: 'Chapter 1', url: 'https://x.com/a/chapter-1'),
    ];

    final ordered = chaptersInReadingOrder(
      links,
      title: (link) => link.title,
      url: (link) => link.url,
    );

    expect(ordered.map((link) => link.title), ['Extra', 'Chapter 1']);
  });
}
