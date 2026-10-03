import '../../../../core/errors/app_exception.dart';
import '../../../../core/storage/database.dart';
import '../../../scraper/domain/models/extracted_chapter.dart';
import '../../../scraper/domain/services/offline_chapter_store.dart';

/// [OfflineChapterStore] backed by JSON files in the app documents
/// directory: one small file per chapter plus a manifest per novel
/// listing the saved chapter URLs in reading order.
class AppDatabaseOfflineChapterStore implements OfflineChapterStore {
  AppDatabaseOfflineChapterStore();

  static const String _manifestPrefix = 'prefetch_';
  static const String _chapterPrefix = 'prefetch_chapter_';

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

    await database.writeJson(_chapterKey(chapter.url), chapter.toJson());

    final manifest = await _readManifest(database, novelKey);
    if (manifest.contains(chapter.url)) return;

    await database.writeJson(_manifestKey(novelKey), [
      ...manifest,
      chapter.url,
    ]);
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

  Future<List<String>> _readManifest(
    AppDatabase database,
    String novelKey,
  ) async {
    try {
      final raw = await database.readJson(
        _manifestKey(novelKey),
        (json) => json,
      );
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
