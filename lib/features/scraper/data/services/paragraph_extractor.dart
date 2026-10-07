import 'package:html/dom.dart';

/// Extracts paragraph lines from [content].
///
/// Prefers `<p>` elements; when the site separates lines with `<br>`
/// instead (no `<p>` at all), falls back to splitting the text on
/// those line breaks. Hidden blocks (search dialogs, logins) are
/// never mistaken for chapter text.
List<String> extractParagraphs(Element content) {
  final paragraphs =
      content
          .querySelectorAll('p')
          .where((element) => !isHidden(element))
          .map((element) => element.text.trim())
          .where((text) => text.isNotEmpty)
          .toList();

  if (paragraphs.isNotEmpty) {
    return paragraphs;
  }

  return extractBrLines(content);
}

/// Splits the text of [content] into lines at every `<br>` element,
/// skipping hidden subtrees.
List<String> extractBrLines(Element content) {
  final buffer = StringBuffer();

  void walk(Node node) {
    if (node is Text) {
      buffer.write(node.text);
      return;
    }

    if (node is Element) {
      if (isHidden(node)) {
        return;
      }

      if (node.localName == 'br') {
        buffer.write('\n');
      } else {
        node.nodes.forEach(walk);
      }
    }
  }

  content.nodes.forEach(walk);

  return buffer
      .toString()
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

/// Whether [element] or one of its ancestors is hidden with an
/// inline `display:none` style.
bool isHidden(Element element) {
  Node? node = element;

  while (node is Element) {
    final style = node.attributes['style']?.toLowerCase().replaceAll(' ', '');

    if (style != null && style.contains('display:none')) {
      return true;
    }

    node = node.parent;
  }

  return false;
}
