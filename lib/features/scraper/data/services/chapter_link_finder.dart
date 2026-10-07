import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

/// A chapter link discovered in a page's table of contents.
class ChapterLink {
  const ChapterLink({required this.title, required this.url});

  final String title;
  final String url;
}

/// Finds the chapter links on a series or contents page.
///
/// Heuristic by design: keeps same-host links whose title or path
/// look like a chapter (numbers, "chapter"/"episode" markers),
/// deduplicated in the order the page lists them. Contents pages
/// routinely link a handful of other series too, so the biggest
/// group of siblings wins.
List<ChapterLink> findChapterLinks(String html, Uri pageUrl) {
  final document = parser.parse(html);

  final seen = <String>{};
  final chapters = <ChapterLink>[];

  void consider(String? href, String title, {bool allowSelf = false}) {
    if (href == null || href.isEmpty) {
      return;
    }

    final lowered = href.toLowerCase();

    if (lowered.startsWith('#') ||
        lowered.startsWith('javascript') ||
        lowered.startsWith('mailto')) {
      return;
    }

    final Uri resolved;

    try {
      resolved = pageUrl.resolve(href);
    } catch (_) {
      return;
    }

    if (resolved.scheme != 'http' && resolved.scheme != 'https') {
      return;
    }

    if (resolved.host != pageUrl.host) {
      return;
    }

    final url = _withoutFragment(resolved);

    if (!allowSelf && url == _withoutFragment(pageUrl)) {
      return;
    }

    if (title.isEmpty || !_looksLikeChapter(title, resolved)) {
      return;
    }

    if (seen.add(url)) {
      chapters.add(ChapterLink(title: title, url: url));
    }
  }

  // A jump menu is the page's own chapter list, so its labels win
  // over whatever the surrounding links call the same chapter. The
  // option pointing back at the open page is the one chapter a
  // reader page never links twice.
  for (final option in document.querySelectorAll('select option')) {
    consider(_optionHref(option), _labelOf(option), allowSelf: true);
  }

  for (final anchor in document.querySelectorAll('a')) {
    consider(anchor.attributes['href'], _titleOf(anchor));
  }

  return _sameSeries(chapters);
}

/// The directory [url] sits in — the series a chapter belongs to —
/// used to group siblings and to key a series' saved chapters.
String chapterDirectoryOf(String url) {
  var path = Uri.tryParse(url)?.path ?? '';

  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }

  final cut = path.lastIndexOf('/');

  return cut <= 0 ? path : path.substring(0, cut);
}

/// Keeps only the chapters that sit in the busiest directory, so a
/// contents page's "you may also like" links do not end up mixed
/// into the series the user actually opened.
List<ChapterLink> _sameSeries(List<ChapterLink> chapters) {
  if (chapters.length < 2) {
    return chapters;
  }

  final groups = <String, int>{};

  for (final chapter in chapters) {
    final directory = chapterDirectoryOf(chapter.url);
    groups[directory] = (groups[directory] ?? 0) + 1;
  }

  if (groups.length < 2) {
    return chapters;
  }

  final sizes = groups.values.toList()..sort((a, b) => b.compareTo(a));

  final largest = sizes.first;

  // A tie (or a lone chapter per group) carries no signal, so the
  // page keeps everything it listed.
  if (largest < 2 || largest <= sizes[1]) {
    return chapters;
  }

  final busiest =
      groups.entries.firstWhere((entry) => entry.value == largest).key;

  return [
    for (final chapter in chapters)
      if (chapterDirectoryOf(chapter.url) == busiest) chapter,
  ];
}

String? _optionHref(Element option) {
  for (final name in const ['value', 'data-c', 'data-href']) {
    final value = option.attributes[name]?.trim();

    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  return null;
}

String _withoutFragment(Uri url) {
  return url.toString().split('#').first;
}

String _titleOf(Element anchor) {
  final text = _labelLeadOf(anchor);

  if (text.isNotEmpty) {
    return text;
  }

  final label = anchor.attributes['aria-label']?.trim();
  if (label != null && label.isNotEmpty) {
    return label;
  }

  final alt = anchor.querySelector('img')?.attributes['alt']?.trim();
  if (alt != null && alt.isNotEmpty) {
    return alt;
  }

  return '';
}

/// The text that names an anchor: everything up to the first piece
/// of text sitting in a leaf element.
///
/// A contents card stacks its label over a subtitle and a date
/// (`Chapter 116`, then `Jo Taechung (2)`, then `2 weeks ago`), and
/// the raw text glues the three together. Walking down to the first
/// leaf keeps the label the row is actually titled by, while a plain
/// `<a>Chapter 1</a>` still reads as its whole text.
String _labelLeadOf(Element anchor) {
  final buffer = StringBuffer();
  var done = false;

  void walk(Node node) {
    if (done) {
      return;
    }

    for (final child in node.nodes) {
      if (done) {
        return;
      }

      if (child is Text) {
        buffer.write(child.text);
        continue;
      }

      if (child is! Element) {
        continue;
      }

      // An icon carries no text, so it never ends the label — its
      // sibling or child still might.
      if (child.children.isEmpty && child.text.trim().isNotEmpty) {
        buffer.write(child.text);
        done = true;
        return;
      }

      walk(child);
    }
  }

  walk(anchor);

  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _labelOf(Element option) {
  return option.text.trim().replaceAll(RegExp(r'\s+'), ' ');
}

bool _looksLikeChapter(String title, Uri url) {
  if (title.contains(RegExp(r'\d'))) {
    return true;
  }

  final lowered = title.toLowerCase();

  if (const ['chapter', 'episode', 'ch.', 'ep.'].any(lowered.contains)) {
    return true;
  }

  final path = url.path.toLowerCase();

  if (path.contains('chapter') || path.contains('episode')) {
    return true;
  }

  if (RegExp(r'/(?:ch|ep|part)[-_]?\d').hasMatch(path)) {
    return true;
  }

  if (url.pathSegments.any((segment) => RegExp(r'^\d+$').hasMatch(segment))) {
    return true;
  }

  return RegExp(r'-\d+$').hasMatch(path);
}
