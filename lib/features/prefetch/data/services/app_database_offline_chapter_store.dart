import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/database.dart';
import '../../../scraper/domain/models/extracted_chapter.dart';
import '../../../scraper/domain/services/offline_chapter_store.dart';
import '../../../scraper/domain/services/offline_image_store.dart';

/// [OfflineChapterStore] backed by JSON files in the app documents
/// directory: one small file per chapter plus a manifest per novel
/// listing the saved chapter URLs in reading order.
///
/// Chapters that carry pictures get them downloaded through
/// [images] before the chapter is recorded, so the copy on disk is
/// readable without a connection.
class AppDatabaseOfflineChapterStore implements OfflineChapterStore {
  AppDatabaseOfflineChapterStore({OfflineImageStore? images})
    : _images = images;

  static const String _manifestPrefix = 'prefetch_';
  static const String _chapterPrefix = 'prefetch_chapter_';

  final OfflineImageStore? _images;

  AppDatabase? _database;

  @override
  Future<List<ExtractedChapter>> load(String novelKey) async {
    final database = await _open();
    if (database == null) return const [];

    try {
      final manifest = await database.readJson(
        _manifestKey(novelKey),
        (json) => json,
      );
      if (manifest is! List) return const [];

      final chapters = <ExtractedChapter>[];
      for (final entry in manifest) {
        if (entry is! String) continue;

        final chapter = await database.readJson(
          _chapterKey(entry),
          ExtractedChapter.fromJson,
        );
        if (chapter != null && chapter.url.isNotEmpty) {
          chapters.add(chapter);
        }
      }
      return chapters;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<int> count(String novelKey) async {
    final database = await _open();
    if (database == null) return 0;

    return (await _readManifest(database, novelKey)).length;
  }

  @override
  Future<void> save(String novelKey, ExtractedChapter chapter) async {
    final database = await _open();
    if (database == null) {
      throw const AppExceptionStorage(message: 'Storage unavailable');
    }

    final ready = await _withOfflineImages(chapter);

    await database.writeJson(_chapterKey(ready.url), ready.toJson());

    final manifest = await _readManifest(database, novelKey);
    if (manifest.contains(ready.url)) return;

    await database.writeJson(_manifestKey(novelKey), [...manifest, ready.url]);
  }

  /// Downloads every picture of an image chapter, so the saved copy
  /// does not depend on the network.
  ///
  /// Pictures that fail keep a `null` path and fall back to the
  /// network while reading; a chapter whose pictures all failed is
  /// not recorded at all.
  Future<ExtractedChapter> _withOfflineImages(ExtractedChapter chapter) async {
    final store = _images;

    if (store == null ||
        chapter.imageUrls.isEmpty ||
        chapter.offlineImagePaths != null) {
      return chapter;
    }

    final paths = <String?>[];

    for (final url in chapter.imageUrls) {
      try {
        paths.add(await store.save(url, referer: chapter.url));
      } catch (_) {
        paths.add(null);
      }
    }

    if (!paths.any((path) => path != null)) {
      throw const PageFetchException(
        'Could not download the chapter pictures.',
      );
    }

    return chapter.copyWith(offlineImagePaths: paths);
  }

  @override
  Future<ExtractedChapter?> find(String url) async {
    final database = await _open();
    if (database == null) return null;

    try {
      return await database.readJson(
        _chapterKey(url),
        ExtractedChapter.fromJson,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> remove(String novelKey) async {
    try {
      final database = await _open();
      if (database == null) return;

      final manifestKey = _manifestKey(novelKey);
      final urls = await _readManifestByKey(database, manifestKey);

      // The same chapter can be saved under two keys, so the copies
      // another novel still lists are left on disk for it.
      final stillWanted =
          urls.isEmpty
              ? const <String>{}
              : await _urlsInOtherManifests(database, manifestKey);

      for (final url in urls) {
        if (!stillWanted.contains(url)) {
          await database.delete(_chapterKey(url));
        }
      }

      await database.delete(manifestKey);
    } catch (_) {
      // Deleting is best effort: a file that will not go away never
      // undoes the removal the user already got.
    }
  }

  /// Every chapter URL any manifest other than [manifestKey] still
  /// lists.
  Future<Set<String>> _urlsInOtherManifests(
    AppDatabase database,
    String manifestKey,
  ) async {
    final shared = <String>{};

    for (final key in await database.keys(prefix: _manifestPrefix)) {
      // Chapter files share the prefix but hold one chapter, not a
      // list of URLs.
      if (key.startsWith(_chapterPrefix) || key == manifestKey) continue;

      shared.addAll(await _readManifestByKey(database, key));
    }

    return shared;
  }

  Future<List<String>> _readManifest(AppDatabase database, String novelKey) {
    return _readManifestByKey(database, _manifestKey(novelKey));
  }

  Future<List<String>> _readManifestByKey(
    AppDatabase database,
    String manifestKey,
  ) async {
    try {
      final raw = await database.readJson(manifestKey, (json) => json);
      if (raw is! List) return [];

      return [
        for (final entry in raw)
          if (entry is String) entry,
      ];
    } catch (_) {
      return [];
    }
  }

  Future<AppDatabase?> _open() async {
    final existing = _database;
    if (existing != null) return existing;

    try {
      _database = await AppDatabase.open();
    } catch (_) {
      return null;
    }

    return _database;
  }

  static String _manifestKey(String novelKey) =>
      '$_manifestPrefix${_hash(novelKey)}';

  static String _chapterKey(String url) => '$_chapterPrefix${_hash(url)}';

  /// djb2 over the string's code units: deterministic across runs
  /// and always a safe file name, unlike the raw URL or novel key.
  static String _hash(String value) {
    var hash = 5381;

    for (final unit in value.codeUnits) {
      hash = ((hash << 5) + hash + unit) & 0x7FFFFFFF;
    }

    return hash.toRadixString(16);
  }
}
