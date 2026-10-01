/// Finds a next/previous navigation link in [document].
///
/// Tries the explicit [selectors] first, then falls back to scanning
/// anchor text (English/Chinese labels and chevrons).
String? findNavigationLink(
  dynamic document,
  Uri currentUrl, {
  required bool isNext,
  List<String> selectors = const [],
}) {
  for (final selector in selectors) {
    final href =
        document.querySelector(selector)?.attributes['href'];

    final resolved = _resolve(currentUrl, href);
    if (resolved != null) {
      return resolved;
    }
  }

  const nextLabels = [
    'next chapter',
    '下一',
    '下页',
    '→',
    '›',
    '»',
  ];

  const previousLabels = [
    'prev chapter',
    'previous chapter',
    '上一',
    '上页',
    '←',
    '‹',
    '«',
  ];

  final labels = isNext ? nextLabels : previousLabels;

  for (final anchor in document.querySelectorAll('a')) {
    final text = anchor.text.trim().toLowerCase();

    if (text.isEmpty) {
      continue;
    }

    final isLabel = isNext
        ? text == 'next' || labels.any(text.contains)
        : text == 'prev' ||
            text == 'previous' ||
            labels.any(text.contains);

    if (!isLabel) {
      continue;
    }

    final resolved = _resolve(currentUrl, anchor.attributes['href']);
    if (resolved != null) {
      return resolved;
    }
  }

  return null;
}

String? _resolve(Uri currentUrl, String? href) {
  if (href == null || href.isEmpty) {
    return null;
  }

  if (href.startsWith('javascript') || href.startsWith('#')) {
    return null;
  }

  return currentUrl.resolve(href).toString();
}
