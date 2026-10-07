import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/network/dio_client.dart';
import 'package:novel_reader/features/reader/presentation/pages/reader_page.dart';
import 'package:novel_reader/features/reader/presentation/providers/chapter_image_loader.dart';
import 'package:novel_reader/features/scraper/data/repositories/scraper_repository.dart';
import 'package:novel_reader/features/scraper/data/services/generic_novel_adapter.dart';
import 'package:novel_reader/features/scraper/domain/models/extracted_chapter.dart';
import 'package:novel_reader/features/scraper/presentation/providers/scraper_providers.dart';
import 'package:novel_reader/features/settings/presentation/providers/settings_provider.dart';

/// A valid 1x1 PNG, so the memory image really decodes.
const String _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
    'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class _FakeScraper extends ScraperRepository {
  _FakeScraper()
    : super(dioClient: DioClient(), adapter: GenericNovelAdapter());

  final Map<String, ExtractedChapter> chapters = <String, ExtractedChapter>{};
  final List<String> requests = <String>[];

  @override
  Future<ExtractedChapter> extractChapter(String url) async {
    requests.add(url);

    final chapter = chapters[url];
    if (chapter == null) {
      throw Exception('No chapter for $url');
    }

    return chapter;
  }
}

class _FakeImageLoader extends ChapterImageLoader {
  _FakeImageLoader({this.fail = false}) : super(DioClient());

  final bool fail;
  final List<String?> referers = <String?>[];

  @override
  Future<Uint8List> load(String url, {String? referer}) async {
    referers.add(referer);

    if (fail) {
      throw const PageFetchException('blocked');
    }

    return base64Decode(_pngBase64);
  }
}

Finder _button(String tooltip) => find.ancestor(
  of: find.byTooltip(tooltip),
  matching: find.byType(IconButton),
);

Widget _buildApp(
  _FakeScraper scraper,
  ExtractedChapter chapter, {
  _FakeImageLoader? loader,
}) {
  return ProviderScope(
    overrides: [
      scraperRepositoryProvider.overrideWithValue(scraper),
      chapterImageLoaderProvider.overrideWithValue(
        loader ?? _FakeImageLoader(),
      ),
    ],
    child: MaterialApp(home: ReaderPage(chapter: chapter)),
  );
}

const pictureChapter = ExtractedChapter(
  title: 'Picture one',
  paragraphs: [],
  url: 'https://example.com/ch-1',
  imageUrls: [
    'https://cdn.example.com/1.jpg',
    'https://cdn.example.com/2.jpg',
    'https://cdn.example.com/3.jpg',
  ],
  nextChapterUrl: 'https://example.com/ch-2',
  previousChapterUrl: 'https://example.com/ch-0',
);

const savedChapter = ExtractedChapter(
  title: 'Saved one',
  paragraphs: [],
  url: 'https://example.com/ch-saved',
  imageUrls: ['/a.jpg', '/b.jpg'],
  offlineImagePaths: ['/docs/manhwa/a.jpg', null],
);

void main() {
  testWidgets('an image chapter renders its pictures and text controls', (
    tester,
  ) async {
    final scraper =
        _FakeScraper()
          ..chapters['https://example.com/ch-2'] = const ExtractedChapter(
            title: 'Two',
            paragraphs: ['Second chapter text'],
            url: 'https://example.com/ch-2',
            previousChapterUrl: 'https://example.com/ch-1',
          );
    final loader = _FakeImageLoader();

    await tester.pumpWidget(_buildApp(scraper, pictureChapter, loader: loader));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNWidgets(3));
    expect(
      tester.widgetList<Image>(find.byType(Image)).map((image) => image.image),
      everyElement(isA<MemoryImage>()),
    );
    expect(loader.referers, everyElement('https://example.com/ch-1'));
    expect(find.byTooltip('Translate to English'), findsNothing);
    expect(find.byTooltip('Font size'), findsNothing);
    expect(find.byTooltip('Auto-scroll'), findsOneWidget);
    expect(find.byTooltip('Scroll speed'), findsOneWidget);
    expect(find.byTooltip('Fullscreen'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);

    expect(find.byTooltip('Previous chapter'), findsOneWidget);
    expect(
      tester.widget<IconButton>(_button('Next chapter')).onPressed,
      isNotNull,
    );
  });

  testWidgets('a site that refuses the picture reports it as unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildApp(
        _FakeScraper(),
        pictureChapter,
        loader: _FakeImageLoader(fail: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Image unavailable'), findsNWidgets(3));
  });

  testWidgets('a saved chapter reads its local copies when it has them', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp(_FakeScraper(), savedChapter));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNWidgets(2));

    final images = tester.widgetList<Image>(find.byType(Image)).toList();

    expect(images.first.image, isA<FileImage>());
    expect(images.last.image, isA<MemoryImage>());
  });

  testWidgets('next chapter still works from a picture chapter', (
    tester,
  ) async {
    final scraper =
        _FakeScraper()
          ..chapters['https://example.com/ch-2'] = const ExtractedChapter(
            title: 'Two',
            paragraphs: ['Second chapter text'],
            url: 'https://example.com/ch-2',
            previousChapterUrl: 'https://example.com/ch-1',
          );

    await tester.pumpWidget(_buildApp(scraper, pictureChapter));
    await tester.pumpAndSettle();

    await tester.tap(_button('Next chapter'));
    await tester.pumpAndSettle();

    expect(scraper.requests, ['https://example.com/ch-2']);
    expect(find.text('Second chapter text'), findsOneWidget);
    expect(find.byTooltip('Translate to English'), findsOneWidget);
  });

  testWidgets('fullscreen hides the bars and a tap brings them back', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp(_FakeScraper(), pictureChapter));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byTooltip('Next chapter'), findsOneWidget);
    expect(find.byTooltip('Fullscreen'), findsOneWidget);

    await tester.tap(_button('Fullscreen'));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsNothing);
    expect(find.byTooltip('Next chapter'), findsNothing);
    expect(find.byTooltip('Fullscreen'), findsNothing);

    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byTooltip('Next chapter'), findsOneWidget);
    expect(find.byTooltip('Fullscreen'), findsOneWidget);
  });

  testWidgets('auto-scroll moves through the pictures until toggled off', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp(_FakeScraper(), pictureChapter));
    await tester.pumpAndSettle();

    // Let the fixture pictures decode on the real event loop so the
    // strip gets its full height.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    ScrollPosition position() {
      return tester.state<ScrollableState>(find.byType(Scrollable)).position;
    }

    expect(position().pixels, 0);
    expect(position().maxScrollExtent, greaterThan(0));

    await tester.tap(_button('Auto-scroll'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(position().pixels, greaterThan(0));

    await tester.tap(_button('Auto-scroll'));
    final stopped = position().pixels;

    await tester.pump(const Duration(milliseconds: 500));
    expect(position().pixels, stopped);
  });

  testWidgets('scroll speed opens a slider that changes the pace', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp(_FakeScraper(), pictureChapter));
    await tester.pumpAndSettle();

    await tester.tap(_button('Scroll speed'));
    await tester.pumpAndSettle();

    expect(find.text('Scroll Speed'), findsOneWidget);
    expect(find.text('100 px/s'), findsOneWidget);

    await tester.drag(find.byType(Slider), const Offset(240, 0));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReaderPage)),
    );
    final speed = container.read(settingsProvider).autoScrollSpeed;

    expect(speed, greaterThan(100));
    expect(find.text('${speed.round()} px/s'), findsOneWidget);
  });
}
