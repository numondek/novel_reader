import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/features/scraper/domain/models/extracted_chapter.dart';

void main() {
  test('json round trip keeps pictures and their local copies', () {
    const chapter = ExtractedChapter(
      title: 'Chapter 1',
      paragraphs: [],
      url: 'https://example.com/ch-1',
      novelTitle: 'Demo',
      imageUrls: [
        'https://cdn.example.com/1.jpg',
        'https://cdn.example.com/2.jpg',
      ],
      offlineImagePaths: ['/docs/manhwa/1.jpg', null],
    );

    final restored = ExtractedChapter.fromJson(
      jsonDecode(jsonEncode(chapter.toJson())),
    );

    expect(restored.imageUrls, chapter.imageUrls);
    expect(restored.offlineImagePaths, ['/docs/manhwa/1.jpg', null]);
    expect(restored.paragraphs, isEmpty);
    expect(restored.hasImages, isTrue);
    expect(restored.title, 'Chapter 1');
    expect(restored.url, 'https://example.com/ch-1');
  });

  test('a text chapter round trips without picture fields', () {
    const chapter = ExtractedChapter(
      title: 'Chapter 1',
      paragraphs: ['First chapter text'],
      url: 'https://example.com/ch-1',
    );

    final json = chapter.toJson();
    expect(json.containsKey('imageUrls'), isFalse);
    expect(json.containsKey('offlineImagePaths'), isFalse);

    final restored = ExtractedChapter.fromJson(jsonDecode(jsonEncode(json)));

    expect(restored.imageUrls, isEmpty);
    expect(restored.offlineImagePaths, isNull);
    expect(restored.hasImages, isFalse);
    expect(restored.paragraphs, ['First chapter text']);
  });

  test('copyWith fills the local copies', () {
    const chapter = ExtractedChapter(
      title: 'Chapter 1',
      paragraphs: [],
      url: 'https://example.com/ch-1',
      imageUrls: ['https://cdn.example.com/1.jpg'],
    );

    final withPaths = chapter.copyWith(
      offlineImagePaths: ['/docs/manhwa/1.jpg'],
    );

    expect(withPaths.imageUrls, chapter.imageUrls);
    expect(withPaths.offlineImagePaths, ['/docs/manhwa/1.jpg']);
    expect(withPaths.url, chapter.url);
  });
}
