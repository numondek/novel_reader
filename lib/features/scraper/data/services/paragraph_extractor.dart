import 'package:html/dom.dart';

/// Extracts paragraph lines from [content].
///
/// Prefers `<p>` elements; when the site separates lines with `<br>`
/// instead (no `<p>` at all), falls back to splitting the text on
/// those line breaks.
List<String> extractParagraphs(Element content) {
  final paragraphs = content
      .querySelectorAll('p')
      .map((element) => element.text.trim())
      .where((text) => text.isNotEmpty)
      .toList();

  if (paragraphs.isNotEmpty) {
    return paragraphs;
  }

  return extractBrLines(content);
}

/// Splits the text of [content] into lines at every `<br>` element.
List<String> extractBrLines(Element content) {
  final buffer = StringBuffer();

  void walk(Node node) {
    if (node is Text) {
      buffer.write(node.text);
      return;
    }

    if (node is Element) {
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
