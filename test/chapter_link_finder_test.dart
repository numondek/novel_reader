import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/scraper/data/services/chapter_link_finder.dart';

void main() {
  test('finds chapter links and ignores navigation', () async {
    const html = '''
<html><body>
  <a href="/manhwa/demo">Demo chapter</a>
  <a href="/home">Home</a>
  <a href="/genres/action">Action</a>
  <a href="/manhwa/demo/chapter-1">Chapter 1</a>
  <a href="/manhwa/demo/chapter-1">Chapter 1</a>
  <a href="chapter-2">Chapter 2</a>
  <a href="https://other.org/chapter-3">Chapter 3</a>
  <a href="#comments">Comments</a>
</body></html>
''';

    final chapters = findChapterLinks(
      html,
      Uri.parse('https://example.com/manhwa/demo'),
    );

    expect(chapters, hasLength(2));
    expect(chapters.first.title, 'Chapter 1');
    expect(chapters.first.url, 'https://example.com/manhwa/demo/chapter-1');
    expect(chapters.last.title, 'Chapter 2');
    expect(chapters.last.url, 'https://example.com/manhwa/chapter-2');
  });

  test('recognises numeric and episode paths', () async {
    const html = '''
<html><body>
  <a href="/manhwa/demo/45">45. The duel</a>
  <a href="/manhwa/demo/ep-100">The return</a>
  <a href="/manhwa/demo/special-2">Extra</a>
</body></html>
''';

    final chapters = findChapterLinks(
      html,
      Uri.parse('https://example.com/manhwa/demo'),
    );

    expect(chapters.map((chapter) => chapter.url), [
      'https://example.com/manhwa/demo/45',
      'https://example.com/manhwa/demo/ep-100',
      'https://example.com/manhwa/demo/special-2',
    ]);
  });

  test('falls back to aria labels and image alt text', () async {
    const html = '''
<html><body>
  <a href="/manga/demo/chapter-9" aria-label="Chapter 9"></a>
  <a href="/manga/demo/chapter-10"><img alt="Chapter 10" src="/t.png"></a>
</body></html>
''';

    final chapters = findChapterLinks(
      html,
      Uri.parse('https://example.com/manga/demo'),
    );

    expect(chapters.map((chapter) => chapter.title), [
      'Chapter 9',
      'Chapter 10',
    ]);
  });

  test('a reader jump menu becomes the chapter list', () async {
    const html = '''
<html><body>
  <select name="cars">
    <option value="/reader/en/demo-chapter-3/">Chapter: 3</option>
    <option value="/reader/en/demo-chapter-2/">Chapter: 2</option>
    <option value="" selected>Chapter: 161</option>
  </select>
</body></html>
''';

    final chapters = findChapterLinks(
      html,
      Uri.parse('https://example.com/reader/en/demo-chapter-161/'),
    );

    expect(chapters.map((chapter) => chapter.title), [
      'Chapter: 3',
      'Chapter: 2',
    ]);
    expect(chapters.first.url, 'https://example.com/reader/en/demo-chapter-3/');
  });

  test('a jump menu written in data-c is the chapter list', () async {
    const html = '''
<html><body>
  <h1>Space Cheon-ma 3077 - Chapter 108</h1>
  <select class="navi-change-chapter">
    <option data-c="chapter-108" selected>Chapter 108</option>
    <option data-c="chapter-107">Chapter 107</option>
    <option data-c="chapter-1">Chapter 1</option>
  </select>
  <select class="navi-change-chapter">
    <option data-c="chapter-108" selected>Chapter 108</option>
    <option data-c="chapter-107">Chapter 107</option>
    <option data-c="chapter-1">Chapter 1</option>
  </select>
  <a href="/manga/other/chapter-5">Chapter 5</a>
</body></html>
''';

    final chapters = findChapterLinks(
      html,
      Uri.parse('https://manga18fx.com/manga/space-cheon-ma-3077/chapter-108'),
    );

    expect(chapters.map((chapter) => chapter.title), [
      'Chapter 108',
      'Chapter 107',
      'Chapter 1',
    ]);
    expect(chapters.first.url, contains('/manga/space-cheon-ma-3077/'));
  });

  test('chapters of other series are left out of the list', () async {
    const html = '''
<html><body>
  <a href="/manga/demo/chapter-1">Chapter 1</a>
  <a href="/manga/demo/chapter-2">Chapter 2</a>
  <a href="/manga/demo/chapter-3">Chapter 3</a>
  <a href="/manga/fantasyland/chapter-47">Chapter 47</a>
  <a href="/manga/fantasyland/chapter-46">Chapter 46</a>
</body></html>
''';

    final chapters = findChapterLinks(
      html,
      Uri.parse('https://example.com/manga/demo'),
    );

    expect(chapters.map((chapter) => chapter.url), [
      'https://example.com/manga/demo/chapter-1',
      'https://example.com/manga/demo/chapter-2',
      'https://example.com/manga/demo/chapter-3',
    ]);
  });

  test('two equally sized groups are both kept', () async {
    const html = '''
<html><body>
  <a href="/manga/demo/chapter-1">Chapter 1</a>
  <a href="/manga/demo/chapter-2">Chapter 2</a>
  <a href="/manga/fantasyland/chapter-47">Chapter 47</a>
  <a href="/manga/fantasyland/chapter-46">Chapter 46</a>
</body></html>
''';

    final chapters = findChapterLinks(
      html,
      Uri.parse('https://example.com/manga/demo'),
    );

    expect(chapters, hasLength(4));
  });

  test('a stacked series card reads as the chapter it links to', () async {
    const html = '''
<html><body>
  <a href="/comics/myst-might-mayhem-bd5bdaf8/chapter/116">
    <div>
      <div><span>Chapter 116</span></div>
      <div>Jo Taechung (2)</div>
      <div>2 weeks ago</div>
    </div>
  </a>
  <a href="/comics/myst-might-mayhem-bd5bdaf8/chapter/115">
    <div>
      <div><span>Chapter 115</span></div>
      <div>Jo Taechung (1)</div>
      <div>3 weeks ago</div>
    </div>
  </a>
  <a href="/comics/another-series">Another Series</a>
</body></html>
''';

    final chapters = findChapterLinks(
      html,
      Uri.parse('https://asurascans.com/comics/myst-might-mayhem-bd5bdaf8'),
    );

    expect(chapters.map((chapter) => chapter.title), [
      'Chapter 116',
      'Chapter 115',
    ]);
    expect(
      chapters.first.url,
      'https://asurascans.com/comics/myst-might-mayhem-bd5bdaf8/chapter/116',
    );
  });

  test('a chapter page that lists no chapter lists nothing', () async {
    const html = '''
<html><head>
  <link rel="prev" href="/comics/myst-might-mayhem-bd5bdaf8/chapter/115">
  <link rel="next" href="/comics/myst-might-mayhem-bd5bdaf8/chapter/117">
</head><body>
  <div class="breadcrumb">
    <a href="/comics">Comics</a>
    <a href="/comics/myst-might-mayhem-bd5bdaf8">Myst, Might, Mayhem</a>
  </div>
  <h1>Myst, Might, Mayhem</h1>
</body></html>
''';

    final chapters = findChapterLinks(
      html,
      Uri.parse(
        'https://asurascans.com/comics/myst-might-mayhem-bd5bdaf8/chapter/116',
      ),
    );

    expect(chapters, isEmpty);
  });

  test(
    'a fanmtl contents page keeps its chapters, drops the neighbours',
    () async {
      const html = '''
<html><head><title>Everlasting Dragon Emperor</title></head><body>
<ul>
  <li>
    <a href="/novel/everlasting-dragon-emperor_1.html" title="Everlasting Dragon Emperor Chapter 1">
      <span class="chapter-no ">1</span>
      <strong class="chapter-title"> Chapter 1: Rebirth</strong>
      <time class="chapter-update">797 days ago</time>
    </a>
  </li>
  <li>
    <a href="/novel/everlasting-dragon-emperor_2.html" title="Everlasting Dragon Emperor Chapter 2">
      <span class="chapter-no ">2</span>
      <strong class="chapter-title"> Chapter 2: Condensate</strong>
    </a>
  </li>
  <li>
    <a href="/novel/everlasting-dragon-emperor_3.html" title="Everlasting Dragon Emperor Chapter 3">
      <span class="chapter-no ">3</span>
      <strong class="chapter-title"> Chapter 3: The Way</strong>
    </a>
  </li>
</ul>
<a href="/novel/everlasting-dragon-emperor.html">Everlasting Dragon Emperor</a>
<div class="recommend">
  <a href="/novel/trxs10834.html">
    <figure><img src="/cover1.jpg"></figure>
    <h5>Necromancer's Second-Original Chat Group</h5>
    <div class="novel-stats"><span>Chapter 182</span></div>
  </a>
  <a href="/novel/trxs10832.html">
    <figure><img src="/cover2.jpg"></figure>
    <h5>Sailing: Me, a Saiyan, starts by clashing with Robin</h5>
    <div class="novel-stats"><span>Chapter 210</span></div>
  </a>
</div>
</body></html>
''';

      final chapters = findChapterLinks(
        html,
        Uri.parse(
          'https://www.fanmtl.com/novel/everlasting-dragon-emperor.html',
        ),
      );

      expect(chapters.map((chapter) => chapter.url), [
        'https://www.fanmtl.com/novel/everlasting-dragon-emperor_1.html',
        'https://www.fanmtl.com/novel/everlasting-dragon-emperor_2.html',
        'https://www.fanmtl.com/novel/everlasting-dragon-emperor_3.html',
      ]);
    },
  );
}
