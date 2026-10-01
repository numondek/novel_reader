import 'package:html/parser.dart' as parser;

import '../../domain/models/extracted_chapter.dart';
import '../../domain/services/novel_site_adapter.dart';
import 'navigation_link_finder.dart';
import 'novel_title_extractor.dart';
import 'paragraph_extractor.dart';

class GenericNovelAdapter implements NovelSiteAdapter {
  @override
  bool canHandle(Uri url) {
    return url.hasScheme && url.host.isNotEmpty;
  }

  @override
  Map<String, String> requestHeaders(Uri url) => const {};

  @override
  Future<ExtractedChapter> extract({
    required String html,
    required Uri url,
  }) async {
    final document = parser.parse(html);

    final title = _extractTitle(document);

    final paragraphs = _extractParagraphs(document);

    final nextChapterUrl = _extractNextChapterUrl(
      document,
      url,
    );

    final previousChapterUrl = _extractPreviousChapterUrl(
      document,
      url,
    );

    if (paragraphs.isEmpty) {
      throw Exception(
        'Could not find chapter content on this page.',
      );
    }

    return ExtractedChapter(
      title: title,
      paragraphs: paragraphs,
      url: url.toString(),
      novelTitle: extractNovelTitle(document),
      nextChapterUrl: nextChapterUrl,
      previousChapterUrl: previousChapterUrl,
    );
  }

  String _extractTitle(dynamic document) {
    final h1 = document.querySelector('h1');

    if (h1 != null) {
      final text = h1.text.trim();

      if (text.isNotEmpty) {
        return text;
      }
    }

    final title = document.querySelector('title');

    if (title != null) {
      final text = title.text.trim();

      if (text.isNotEmpty) {
        return text;
      }
    }

    return 'Untitled Chapter';
  }

  List<String> _extractParagraphs(dynamic document) {
    final paragraphs = document
        .querySelectorAll('p')
        .map((element) => element.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    if (paragraphs.isNotEmpty) {
      return paragraphs;
    }

    const contentFallbacks = [
      'article',
      '.content',
      '#content',
      '.chapter-content',
      '#chapter-content',
      '.reading-content',
      '.chapter-inner',
      'main',
      'body',
    ];

    for (final selector in contentFallbacks) {
      final element = document.querySelector(selector);

      if (element == null) {
        continue;
      }

      final lines = extractParagraphs(element);

      if (lines.isNotEmpty) {
        return lines;
      }
    }

    return const [];
  }

  String? _extractNextChapterUrl(
    dynamic document,
    Uri currentUrl,
  ) {
    return findNavigationLink(
      document,
      currentUrl,
      isNext: true,
      selectors: const [
        'a[rel="next"]',
        'a.next',
        'a.next-chapter',
        '#next_url',
      ],
    );
  }

  String? _extractPreviousChapterUrl(
    dynamic document,
    Uri currentUrl,
  ) {
    return findNavigationLink(
      document,
      currentUrl,
      isNext: false,
      selectors: const [
        'a[rel="prev"]',
        'a.prev',
        'a.prev-chapter',
        '#prev_url',
      ],
    );
  }
}
