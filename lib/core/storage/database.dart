import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../errors/app_exception.dart';

/// Lightweight local key/value + JSON document store.
///
/// Small records live in [SharedPreferences]; larger documents (chapters,
/// scraped pages, reading progress) are written as JSON files inside the
/// application documents directory.
class AppDatabase {
  AppDatabase._(this._prefs, this._docsDir);

  static const String _dbName = 'novel_reader.db';

  final SharedPreferences _prefs;
  final Directory _docsDir;

  static Future<AppDatabase> open() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final docsDir = await getApplicationDocumentsDirectory();
      return AppDatabase._(prefs, docsDir);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        AppExceptionStorage(message: 'Failed to open database', cause: error),
        stackTrace,
      );
    }
  }

  Future<void> writeJson(String key, Object value) async {
    try {
      final file = File('${_docsDir.path}${Platform.pathSeparator}$key.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(value), flush: true);
    } catch (error) {
      throw AppExceptionStorage(message: 'Failed to write "$key"', cause: error);
    }
  }

  Future<T?> readJson<T>(
    String key,
    T Function(Object? json) fromJson,
  ) async {
    try {
      final file = File('${_docsDir.path}${Platform.pathSeparator}$key.json');
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      return fromJson(jsonDecode(raw));
    } catch (error) {
      throw AppExceptionStorage(message: 'Failed to read "$key"', cause: error);
    }
  }

  Future<void> delete(String key) async {
    final file = File('${_docsDir.path}${Platform.pathSeparator}$key.json');
    if (await file.exists()) await file.delete();
    await _prefs.remove('$_dbName:$key');
  }

  String? getString(String key) => _prefs.getString('$_dbName:$key');

  Future<void> setString(String key, String value) =>
      _prefs.setString('$_dbName:$key', value);

  bool getBool(String key, {bool fallback = false}) =>
      _prefs.getBool('$_dbName:$key') ?? fallback;

  Future<void> setBool(String key, bool value) =>
      _prefs.setBool('$_dbName:$key', value);

  int getInt(String key, {int fallback = 0}) =>
      _prefs.getInt('$_dbName:$key') ?? fallback;

  Future<void> setInt(String key, int value) =>
      _prefs.setInt('$_dbName:$key', value);
}
