import 'package:html/dom.dart';
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

    final prose = paragraphs.join('\n').trim();

    var images = _extractImages(document, url);

    // A page that is almost all pictures but has no recognised
    // container (a bare reader page) still reads as a strip.
    if (images.isEmpty && prose.length < 300) {
      final body = document.body;

      if (body != null) {
        final bodyImages = _imageUrlsIn(body, url);

        if (bodyImages.length >= 3) {
          images = bodyImages;
        }
      }
    }

    final nextChapterUrl = _extractNextChapterUrl(document, url);

    final previousChapterUrl = _extractPreviousChapterUrl(document, url);

    if (paragraphs.isEmpty && images.isEmpty) {
      throw Exception('Could not find chapter content on this page.');
    }

    // A chapter that is mostly pictures (manhwa/comics) reads as a
    // strip; prose longer than a caption or navigation line keeps
    // the chapter in text mode, illustrations included.
    final comic =
        images.isNotEmpty && (prose.length < 300 || images.length >= 3);

    return ExtractedChapter(
      title: title,
      paragraphs: paragraphs,
      url: url.toString(),
      novelTitle: extractNovelTitle(document),
      nextChapterUrl: nextChapterUrl,
      previousChapterUrl: previousChapterUrl,
      imageUrls: comic ? images : const [],
    );
  }

  String _extractTitle(Document document) {
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

  List<String> _extractParagraphs(Document document) {
    final paragraphs =
        document
            .querySelectorAll('p')
            .where((element) => !isHidden(element))
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
      for (final element in document.querySelectorAll(selector)) {
        if (isHidden(element)) {
          continue;
        }

        final lines = extractParagraphs(element);

        if (lines.isNotEmpty) {
          return lines;
        }
      }
    }

    return const [];
  }

  /// Collects the chapter's pictures from the content area, in
  /// reading order — skipping logos, ads and other decorations.
  List<String> _extractImages(Document document, Uri url) {
    const imageSelectors = [
      '#chapter-reader',
      '#chapter-content',
      '.chapter-content',
      '.chapter-images',
      '.reading-content',
      '.read-content',
      '.comics',
      '.webtoon',
      '.chapter-inner',
      '.entry-content',
      '.content',
      '#content',
      'article',
    ];

    List<String>? small;

    for (final selector in imageSelectors) {
      final container = document.querySelector(selector);

      if (container == null) {
        continue;
      }

      final urls = _imageUrlsIn(container, url);

      if (urls.length >= 3) {
        return urls;
      }

      small ??= urls.isEmpty ? null : urls;
    }

    return small ?? const [];
  }

  List<String> _imageUrlsIn(Element container, Uri baseUrl) {
    final seen = <String>{};
    final urls = <String>[];

    for (final image in container.querySelectorAll('img')) {
      final source = _imageSource(image);

      if (source == null) {
        continue;
      }

      final width = int.tryParse(image.attributes['width'] ?? '');
      if (width != null && width > 0 && width < 64) {
        continue;
      }

      final resolved = baseUrl.resolve(source);

      if (resolved.scheme != 'http' && resolved.scheme != 'https') {
        continue;
      }

      if (!_isChapterImage(resolved)) {
        continue;
      }

      if (seen.add(resolved.toString())) {
        urls.add(resolved.toString());
      }
    }

    return urls;
  }

  /// The real image address, preferring the lazy-load attribute most
  /// comic sites use over the placeholder in `src`.
  String? _imageSource(Element image) {
    final attributes = image.attributes;

    const lazyAttributes = [
      'data-src',
      'data-lazy-src',
      'data-original',
      'data-url',
      'src',
    ];

    for (final name in lazyAttributes) {
      final value = attributes[name]?.trim();

      if (value == null || value.isEmpty || value.startsWith('data:')) {
        continue;
      }

      return value;
    }

    final candidates =
        (attributes['srcset'] ?? '')
            .split(',')
            .map((candidate) => candidate.trim().split(RegExp(r'\s+')).first)
            .where(
              (candidate) =>
                  candidate.isNotEmpty && !candidate.startsWith('data:'),
            )
            .toList();

    return candidates.isEmpty ? null : candidates.last;
  }

  bool _isChapterImage(Uri image) {
    final path = image.path.toLowerCase();

    if (path.endsWith('.svg')) {
      return false;
    }

    const decorations = [
      'logo',
      'icon',
      'avatar',
      'banner',
      'advert',
      '/ads/',
      'emoji',
      'spinner',
      'placeholder',
    ];

    return !decorations.any(path.contains);
  }

  String? _extractNextChapterUrl(Document document, Uri currentUrl) {
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

  String? _extractPreviousChapterUrl(Document document, Uri currentUrl) {
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
