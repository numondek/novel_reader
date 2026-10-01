/// Extracts the novel (book) title from a chapter page.
///
/// Sources, in order: `og:novel:*` meta tags (used by freewebnovel
/// and similar sites), 《...》 markers in heading elements, and the
/// last breadcrumb link (czbooks style, with the 《目錄》 suffix
/// stripped). Returns null when the page carries no novel name.
String? extractNovelTitle(dynamic document) {
  const metaSelectors = [
    'meta[property="og:novel:novel_name"]',
    'meta[property="og:novel:book_name"]',
    'meta[property="og:book_name"]',
    'meta[name="novel_name"]',
    'meta[name="book_name"]',
  ];

  for (final selector in metaSelectors) {
    final content = document
        .querySelector(selector)
        ?.attributes['content']
        ?.trim();

    if (content != null && content.isNotEmpty) {
      return content;
    }
  }

  const markerSelectors = [
    'h1',
    '.name',
    '#bookname',
    '.book-name',
    '.novel-name',
  ];

  final bracketPattern = RegExp(r'《([^》]+)》');

  for (final selector in markerSelectors) {
    final text = document.querySelector(selector)?.text;
    if (text == null) continue;

    final match = bracketPattern.firstMatch(text);
    if (match != null) {
      final name = match.group(1)?.trim();
      if (name != null && name.isNotEmpty) {
        return name;
      }
    }
  }

  const breadcrumbSelectors = [
    '.position a',
    '.breadcrumb a',
    'nav.breadcrumb a',
    '#breadcrumb a',
    '.breadcrumbs a',
  ];

  const catalogWords = {
    '目錄',
    '目录',
    '目 录',
    'Contents',
    'Table of Contents',
    'Catalog',
  };

  for (final selector in breadcrumbSelectors) {
    final links = document.querySelectorAll(selector);
    if (links.isEmpty) continue;

    var text = links.last.text
        .replaceFirst(RegExp(r'\s*《目[錄录]》\s*$'), '')
        .trim();

    if (catalogWords.contains(text) && links.length > 1) {
      text = links[links.length - 2].text.trim();
    }

    if (text.isEmpty || text.length > 80) {
      continue;
    }

    if (catalogWords.contains(text)) {
      continue;
    }

    return text;
  }

  return null;
}
