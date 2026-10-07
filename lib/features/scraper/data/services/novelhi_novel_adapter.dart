import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import '../../domain/services/novel_site_adapter.dart';
import 'api_payload.dart';
import 'generic_novel_adapter.dart';

/// novelhi.com keeps the chapter text behind a token-gated endpoint
/// that only answers with the page's own headers, so the markup is
/// fetched, and the obfuscated text decoded, after the page arrives.
class NovelhiAdapter extends GenericNovelAdapter implements ChapterHtmlRefiner {
  @override
  bool canHandle(Uri url) {
    final host = url.host.toLowerCase();
    return host == 'novelhi.com' || host.endsWith('.novelhi.com');
  }

  @override
  Map<String, String> requestHeaders(Uri url) {
    if (url.path.endsWith('/content')) {
      return const {
        'X-Requested-With': 'XMLHttpRequest',
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'Referer': 'https://novelhi.com/',
      };
    }

    return const {};
  }

  @override
  Future<String> refine({
    required String html,
    required Uri url,
    required Future<String> Function(Uri url) load,
  }) async {
    final document = parser.parse(html);

    final path =
        document.querySelector('#chapterContentPath')?.attributes['value'];
    final token =
        document.querySelector('#chapterContentToken')?.attributes['value'];

    // No endpoint on this page, a gate or a login wall: what the
    // page itself shows is all there is.
    if (path == null || path.isEmpty || token == null || token.isEmpty) {
      return html;
    }

    final contentUri = url.resolve(
      '$path?token=${Uri.encodeQueryComponent(token)}',
    );

    final data = decodeJsonPayload(await load(contentUri));
    final payload = data['data'];

    if (payload is! Map) {
      return html;
    }

    final content = payload['content'];
    if (content is! String || content.isEmpty) {
      return html;
    }

    final fragment = parser.parseFragment(content);

    if (payload['fontObfuscation'] == true) {
      _decodeTextNodes(fragment);
    }

    final paragraphs = _paragraphsOf(fragment);

    document
        .querySelectorAll('script, style, .orderBox, p')
        .forEach((element) => element.remove());

    final target = document.querySelector('#showReading') ?? document.body;

    if (target == null) {
      return html;
    }

    target.innerHtml = '';
    target.nodes.addAll(paragraphs);

    return document.outerHtml;
  }

  /// The chapter's text as paragraphs: the `<p>`s some chapters
  /// ship as, the obfuscated `<sent>` runs most ship as, or plain
  /// text broken at its `<br>`s.
  List<Element> _paragraphsOf(DocumentFragment fragment) {
    final existing =
        fragment
            .querySelectorAll('p')
            .where((element) => element.text.trim().isNotEmpty)
            .toList();

    if (existing.isNotEmpty) {
      return existing;
    }

    final wrapped = <Element>[];

    for (final sent in fragment.querySelectorAll('sent')) {
      final text = sent.text.trim();

      if (text.isNotEmpty) {
        wrapped.add(Element.tag('p')..text = text);
      }
    }

    if (wrapped.isNotEmpty) {
      return wrapped;
    }

    final lines = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final text = buffer.toString().trim();
      if (text.isNotEmpty) {
        lines.add(text);
      }
      buffer.clear();
    }

    void walk(Node node) {
      for (final child in node.nodes) {
        if (child is Text) {
          buffer.write(child.text);
          continue;
        }

        if (child is! Element) {
          continue;
        }

        final name = child.localName;

        if (name == 'script' || name == 'style') {
          continue;
        }

        if (name == 'br') {
          flush();
          continue;
        }

        walk(child);

        if (name == 'div' || name == 'p') {
          flush();
        }
      }
    }

    walk(fragment);
    flush();

    return [for (final line in lines) Element.tag('p')..text = line];
  }

  /// ROT13, the site's glyph obfuscation of the chapter text.
  void _decodeTextNodes(Node node) {
    for (final child in node.nodes.toList()) {
      if (child is Text) {
        child.text = _rot13(child.text);
      } else if (child is Element) {
        final name = child.localName;
        if (name == 'script' || name == 'style') {
          continue;
        }
        _decodeTextNodes(child);
      }
    }
  }

  String _rot13(String text) {
    final buffer = StringBuffer();

    for (final code in text.runes) {
      if (code >= 97 && code <= 122) {
        buffer.writeCharCode(((code - 97 + 13) % 26) + 97);
      } else if (code >= 65 && code <= 90) {
        buffer.writeCharCode(((code - 65 + 13) % 26) + 65);
      } else {
        buffer.writeCharCode(code);
      }
    }

    return buffer.toString();
  }
}
