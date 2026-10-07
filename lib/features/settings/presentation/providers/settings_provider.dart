import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/database.dart';

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// User preferences: display, reading and text-to-speech voice.
class AppSettings {
  const AppSettings({
    this.fontSize = 18,
    this.autoScroll = true,
    this.autoScrollSpeed = 100,
    this.speechRate = 0.5,
    this.voiceName,
    this.voiceLocale,
    this.darkMode = false,
  });

  /// Reader font size in logical pixels (14–32).
  final int fontSize;

  /// Whether the reader follows the narration automatically.
  final bool autoScroll;

  /// Continuous auto-scroll speed for picture chapters, in logical
  /// pixels per second (20–400).
  final double autoScrollSpeed;

  /// Text-to-speech rate (0.1–1.0).
  final double speechRate;

  /// Device voice selected for narration; null = system default.
  final String? voiceName;
  final String? voiceLocale;

  /// Whether the app uses the dark theme.
  final bool darkMode;

  AppSettings copyWith({
    int? fontSize,
    bool? autoScroll,
    double? autoScrollSpeed,
    double? speechRate,
    bool? darkMode,
  }) {
    return AppSettings(
      fontSize: fontSize ?? this.fontSize,
      autoScroll: autoScroll ?? this.autoScroll,
      autoScrollSpeed: autoScrollSpeed ?? this.autoScrollSpeed,
      speechRate: speechRate ?? this.speechRate,
      voiceName: voiceName,
      voiceLocale: voiceLocale,
      darkMode: darkMode ?? this.darkMode,
    );
  }

  AppSettings withVoice(String? name, String? locale) {
    return AppSettings(
      fontSize: fontSize,
      autoScroll: autoScroll,
      autoScrollSpeed: autoScrollSpeed,
      speechRate: speechRate,
      voiceName: name,
      voiceLocale: locale,
      darkMode: darkMode,
    );
  }
}

/// Loads preferences once and persists every change to
/// [AppDatabase]; falls back to defaults when storage is
/// unavailable (e.g. in tests).
class SettingsController extends Notifier<AppSettings> {
  static const String fontKey = 'settings.font_size';
  static const String autoScrollKey = 'settings.auto_scroll';
  static const String autoScrollSpeedKey = 'settings.auto_scroll_speed';
  static const String speechRateKey = 'settings.speech_rate';
  static const String voiceKey = 'settings.voice';
  static const String voiceLocaleKey = 'settings.voice_locale';
  static const String darkModeKey = 'settings.dark_mode';

  static const int minFontSize = 14;
  static const int maxFontSize = 32;
  static const double minAutoScrollSpeed = 20;
  static const double maxAutoScrollSpeed = 400;
  static const double minSpeechRate = 0.1;
  static const double maxSpeechRate = 1.0;

  late final Future<AppDatabase?> _ready;

  /// Keys the user changed before the async load finished;
  /// a slow load must not clobber the fresher in-memory value.
  final Set<String> _dirtyKeys = {};

  @override
  AppSettings build() {
    _ready = _open();
    _ready.then(_apply);
    return const AppSettings();
  }

  Future<AppDatabase?> _open() async {
    try {
      return await AppDatabase.open();
    } catch (_) {
      return null;
    }
  }

  Future<void> _apply(AppDatabase? db) async {
    if (db == null) return;

    state = AppSettings(
      fontSize:
          _dirtyKeys.contains(fontKey)
              ? state.fontSize
              : db.getInt(fontKey, fallback: 18),
      autoScroll:
          _dirtyKeys.contains(autoScrollKey)
              ? state.autoScroll
              : db.getBool(autoScrollKey, fallback: true),
      autoScrollSpeed:
          _dirtyKeys.contains(autoScrollSpeedKey)
              ? state.autoScrollSpeed
              : double.tryParse(db.getString(autoScrollSpeedKey) ?? '') ?? 100,
      speechRate:
          _dirtyKeys.contains(speechRateKey)
              ? state.speechRate
              : double.tryParse(db.getString(speechRateKey) ?? '') ?? 0.5,
      voiceName:
          _dirtyKeys.contains(voiceKey)
              ? state.voiceName
              : _nonEmpty(db.getString(voiceKey)),
      voiceLocale:
          _dirtyKeys.contains(voiceLocaleKey)
              ? state.voiceLocale
              : _nonEmpty(db.getString(voiceLocaleKey)),
      darkMode:
          _dirtyKeys.contains(darkModeKey)
              ? state.darkMode
              : db.getBool(darkModeKey, fallback: false),
    );
  }

  String? _nonEmpty(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<AppDatabase?> _persist(
    Future<void> Function(AppDatabase db) write,
  ) async {
    final db = await _ready;
    if (db == null) return null;

    try {
      await write(db);
    } catch (_) {
      // Best effort: keep the in-memory value.
    }

    return db;
  }

  Future<void> setFontSize(int value) async {
    final clamped = value.clamp(minFontSize, maxFontSize);

    _dirtyKeys.add(fontKey);
    state = state.copyWith(fontSize: clamped);
    await _persist((db) => db.setInt(fontKey, clamped));
  }

  Future<void> setAutoScroll(bool value) async {
    _dirtyKeys.add(autoScrollKey);
    state = state.copyWith(autoScroll: value);
    await _persist((db) => db.setBool(autoScrollKey, value));
  }

  Future<void> setAutoScrollSpeed(double value) async {
    final clamped =
        value.clamp(minAutoScrollSpeed, maxAutoScrollSpeed).toDouble();

    _dirtyKeys.add(autoScrollSpeedKey);
    state = state.copyWith(autoScrollSpeed: clamped);
    await _persist(
      (db) => db.setString(autoScrollSpeedKey, clamped.toStringAsFixed(0)),
    );
  }

  Future<void> setDarkMode(bool value) async {
    _dirtyKeys.add(darkModeKey);
    state = state.copyWith(darkMode: value);
    await _persist((db) => db.setBool(darkModeKey, value));
  }

  Future<void> setSpeechRate(double value) async {
    final clamped = value.clamp(minSpeechRate, maxSpeechRate).toDouble();

    _dirtyKeys.add(speechRateKey);
    state = state.copyWith(speechRate: clamped);
    await _persist(
      (db) => db.setString(speechRateKey, clamped.toStringAsFixed(2)),
    );
  }

  Future<void> setVoice(String? name, String? locale) async {
    _dirtyKeys
      ..add(voiceKey)
      ..add(voiceLocaleKey);
    state = state.withVoice(name, locale);
    await _persist((db) async {
      await db.setString(voiceKey, name ?? '');
      await db.setString(voiceLocaleKey, locale ?? '');
    });
  }
}
