import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/core/network/dio_client.dart';
import 'package:novel_reader/features/scraper/data/repositories/scraper_repository.dart';
import 'package:novel_reader/features/scraper/data/services/generic_novel_adapter.dart';
import 'package:novel_reader/features/scraper/domain/models/extracted_chapter.dart';
import 'package:novel_reader/features/scraper/domain/services/offline_chapter_store.dart';

class _ExplodingDio extends DioClient {
  @override
  Future<String> getHtml(String url, {Map<String, String>? headers}) async {
    throw StateError('network used');
  }
}

class _MapStore implements OfflineChapterStore {
  _MapStore(this.saved);

  final Map<String, ExtractedChapter> saved;

  @override
  Future<List<ExtractedChapter>> load(String novelKey) async => const [];

  @override
  Future<int> count(String novelKey) async => saved.length;

  @override
  Future<void> save(String novelKey, ExtractedChapter chapter) async {}

  @override
  Future<ExtractedChapter?> find(String url) async => saved[url];
}

class _ThrowingStore implements OfflineChapterStore {
  @override
  Future<List<ExtractedChapter>> load(String novelKey) =>
      Future.error(StateError('storage down'));

  @override
  Future<int> count(String novelKey) =>
      Future.error(StateError('storage down'));

  @override
  Future<void> save(String novelKey, ExtractedChapter chapter) =>
      Future.error(StateError('storage down'));

  @override
  Future<ExtractedChapter?> find(String url) =>
      Future.error(StateError('storage down'));
}

const cachedChapter = ExtractedChapter(
  title: 'One',
  paragraphs: <String>['Cached text'],
  url: 'https://example.com/1',
);

void main() {
  test('a saved chapter is returned without touching the network', () async {
    final repository = ScraperRepository(
      dioClient: _ExplodingDio(),
      adapter: GenericNovelAdapter(),
      offline: _MapStore({'https://example.com/1': cachedChapter}),
    );

    final chapter = await repository.extractChapter('https://example.com/1');

    expect(chapter, same(cachedChapter));
  });

  test('without a saved copy the fetch goes to the network', () async {
    final repository = ScraperRepository(
      dioClient: _ExplodingDio(),
      adapter: GenericNovelAdapter(),
    );

    expect(
      repository.extractChapter('https://example.com/1'),
      throwsA(isA<StateError>()),
    );
  });

  test('storage trouble falls through to the network', () async {
    final repository = ScraperRepository(
      dioClient: _ExplodingDio(),
      adapter: GenericNovelAdapter(),
      offline: _ThrowingStore(),
    );

    expect(
      repository.extractChapter('https://example.com/1'),
      throwsA(isA<StateError>()),
    );
  });
}
