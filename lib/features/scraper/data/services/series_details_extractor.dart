import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import 'novel_title_extractor.dart';

/// What a series looks like on the shelf: its name and, when the
/// page offers one, the cover that goes on the front of the card.
class SeriesDetails {
  const SeriesDetails({required this.title, this.coverUrl});

  final String title;
  final String? coverUrl;
}

/// Reads the series' title and cover out of a series or chapter
/// page, so a manhwa the user opened can be recognised later.
SeriesDetails extractSeriesDetails(String html, Uri pageUrl) {
  final document = parser.parse(html);
  final siteName = _meta(document, 'og:site_name');

  return SeriesDetails(
    title: _title(document, pageUrl, siteName),
    coverUrl: _cover(document, pageUrl),
  );
}

String _title(Document document, Uri pageUrl, String? siteName) {
  final sources = <String?>[
    extractNovelTitle(document),
    document.querySelector('h1')?.text,
    _meta(document, 'og:title'),
    document.querySelector('title')?.text,
    _fromSlug(pageUrl),
  ];

  for (final source in sources) {
    final title = _cleanTitle(source, siteName);
    if (title != null) {
      return title;
    }
  }

  return pageUrl.host;
}

/// Removes the chapter and site suffixes sites fold into a page's
/// title — "Space Cheon-ma 3077 - Chapter 108 - Manga18fx" is the
/// series "Space Cheon-ma 3077".
String? _cleanTitle(String? raw, String? siteName) {
  var text = raw?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

  if (text.isEmpty) {
    return null;
  }

  text = text.replaceFirst(
    RegExp(
      r'\s*[-–—|:]?\s*(?:Chapter|Episode)\s*#?\d+.*$',
      caseSensitive: false,
    ),
    '',
  );

  final site = siteName?.trim() ?? '';
  if (site.isNotEmpty &&
      text.toLowerCase().endsWith(' - ${site.toLowerCase()}')) {
    text = text.substring(0, text.length - site.length - 3).trim();
  }

  text = text.replaceAll(RegExp(r'\s*[-–—|:]\s*$'), '').trim();

  if (text.isEmpty) {
    return null;
  }

  if (RegExp(
    r'^(?:Chapter|Episode)\s*#?\d+$',
    caseSensitive: false,
  ).hasMatch(text)) {
    return null;
  }

  return text;
}

String? _cover(Document document, Uri pageUrl) {
  const selectors = [
    'meta[property="og:image"]',
    'meta[name="twitter:image"]',
    'link[rel="image_src"]',
  ];

  for (final selector in selectors) {
    final element = document.querySelector(selector);
    final content =
        element?.attributes['content'] ?? element?.attributes['href'];

    final value = content?.trim() ?? '';
    if (value.isEmpty || value.startsWith('data:')) {
      continue;
    }

    final Uri resolved;

    try {
      resolved = pageUrl.resolve(value);
    } catch (_) {
      continue;
    }

    if (resolved.scheme == 'http' || resolved.scheme == 'https') {
      return resolved.toString();
    }
  }

  return null;
}

String? _meta(Document document, String property) {
  return document
      .querySelector('meta[property="$property"]')
      ?.attributes['content']
      ?.trim();
}

/// Falls back to the page's own address — `/manga/space-3077` still
/// says what the series is called when nothing else does.
String? _fromSlug(Uri url) {
  final segments = [
    for (final segment in url.pathSegments)
      if (segment.trim().isNotEmpty) segment.trim(),
  ];

  if (segments.isEmpty) {
    return null;
  }

  final slug = segments.last;

  if (RegExp(
    r'^(?:chapter|episode|ch|ep)[-_]?\d+$',
    caseSensitive: false,
  ).hasMatch(slug)) {
    return segments.length > 1
        ? _prettify(segments[segments.length - 2])
        : null;
  }

  if (RegExp(r'^\d+$').hasMatch(slug)) {
    return segments.length > 1
        ? _prettify(segments[segments.length - 2])
        : null;
  }

  return _prettify(slug);
}

String _prettify(String slug) {
  final words =
      slug
          .replaceAll(RegExp(r'[_]+'), ' ')
          .split(RegExp(r'[-]+'))
          .map((word) => word.trim())
          .where((word) => word.isNotEmpty)
          .toList();

  return words
      .map((word) {
        final lower = word.toLowerCase();

        if (RegExp(r'^\d+$').hasMatch(word)) {
          return word;
        }

        return lower[0].toUpperCase() + lower.substring(1);
      })
      .join(' ');
}
