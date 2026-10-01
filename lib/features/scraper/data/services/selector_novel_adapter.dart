import 'package:html/parser.dart' as parser;

import '../../domain/models/extracted_chapter.dart';
import '../../domain/services/novel_site_adapter.dart';
import 'navigation_link_finder.dart';
import 'novel_title_extractor.dart';
import 'paragraph_extractor.dart';

/// Base adapter for sites whose chapter content lives under a
/// single, known CSS selector.
abstract class SelectorNovelAdapter implements NovelSiteAdapter {
  const SelectorNovelAdapter();

  /// Host fragments this adapter is responsible for.
  List<String> get hosts;

  /// CSS selector that wraps the chapter text.
  String get contentSelector;

  @override
  bool canHandle(Uri url) {
    final host = url.host.toLowerCase();
    return hosts.any(host.contains);
  }

  @override
  Map<String, String> requestHeaders(Uri url) => const {};

  @override
  Future<ExtractedChapter> extract({
    required String html,
    required Uri url,
  }) async {
    final document = parser.parse(html);

    document
        .querySelectorAll('subtxt, .reader-ad-skip, script, style')
        .forEach((element) => element.remove());

    final content = document.querySelector(contentSelector);

    if (content == null) {
      throw Exception(
        'No content found for $contentSelector on ${url.host}.',
      );
    }

    final paragraphs = extractParagraphs(content);

    if (paragraphs.isEmpty) {
      throw Exception(
        'Could not find chapter content on this page.',
      );
    }

    return ExtractedChapter(
      title: extractTitle(document),
      paragraphs: paragraphs,
      url: url.toString(),
      novelTitle: extractNovelTitle(document),
      nextChapterUrl: extractNextChapterUrl(document, url),
      previousChapterUrl: extractPreviousChapterUrl(document, url),
    );
  }

  String extractTitle(dynamic document) {
    final heading = document.querySelector('h1');

    final headingText = heading?.text.trim();
    if (headingText != null && headingText.isNotEmpty) {
      return headingText;
    }

    final title = document.querySelector('title')?.text.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }

    return 'Untitled Chapter';
  }

  String? extractNextChapterUrl(dynamic document, Uri currentUrl) {
    return findNavigationLink(
      document,
      currentUrl,
      isNext: true,
      selectors: const [
        '#next_url',
        'a.next',
        'a.next-chapter',
        'a.next-btn',
        'a[rel="next"]',
      ],
    );
  }

  String? extractPreviousChapterUrl(dynamic document, Uri currentUrl) {
    return findNavigationLink(
      document,
      currentUrl,
      isNext: false,
      selectors: const [
        '#prev_url',
        'a.prev',
        'a.prev-chapter',
        'a[rel="prev"]',
      ],
    );
  }
}
