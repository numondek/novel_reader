// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

part of 'app_router.dart';

/// generated route for
/// [AudioPage]
class AudioRoute extends PageRouteInfo<void> {
  const AudioRoute({List<PageRouteInfo>? children})
    : super(AudioRoute.name, initialChildren: children);

  static const String name = 'AudioRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const AudioPage();
    },
  );
}

/// generated route for
/// [HomePage]
class HomeRoute extends PageRouteInfo<void> {
  const HomeRoute({List<PageRouteInfo>? children})
    : super(HomeRoute.name, initialChildren: children);

  static const String name = 'HomeRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const HomePage();
    },
  );
}

/// generated route for
/// [LibraryPage]
class LibraryRoute extends PageRouteInfo<void> {
  const LibraryRoute({List<PageRouteInfo>? children})
    : super(LibraryRoute.name, initialChildren: children);

  static const String name = 'LibraryRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const LibraryPage();
    },
  );
}

/// generated route for
/// [NovelImportPage]
class NovelImportRoute extends PageRouteInfo<NovelImportRouteArgs> {
  NovelImportRoute({
    Key? key,
    required String url,
    List<PageRouteInfo>? children,
  }) : super(
         NovelImportRoute.name,
         args: NovelImportRouteArgs(key: key, url: url),
         initialChildren: children,
       );

  static const String name = 'NovelImportRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<NovelImportRouteArgs>();
      return NovelImportPage(key: args.key, url: args.url);
    },
  );
}

class NovelImportRouteArgs {
  const NovelImportRouteArgs({this.key, required this.url});

  final Key? key;

  final String url;

  @override
  String toString() {
    return 'NovelImportRouteArgs{key: $key, url: $url}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NovelImportRouteArgs) return false;
    return key == other.key && url == other.url;
  }

  @override
  int get hashCode => key.hashCode ^ url.hashCode;
}

/// generated route for
/// [NovelsPage]
class NovelsRoute extends PageRouteInfo<void> {
  const NovelsRoute({List<PageRouteInfo>? children})
    : super(NovelsRoute.name, initialChildren: children);

  static const String name = 'NovelsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const NovelsPage();
    },
  );
}

/// generated route for
/// [PrefetchPage]
class PrefetchRoute extends PageRouteInfo<void> {
  const PrefetchRoute({List<PageRouteInfo>? children})
    : super(PrefetchRoute.name, initialChildren: children);

  static const String name = 'PrefetchRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const PrefetchPage();
    },
  );
}

/// generated route for
/// [ReaderPage]
class ReaderRoute extends PageRouteInfo<ReaderRouteArgs> {
  ReaderRoute({
    Key? key,
    ExtractedChapter? chapter,
    List<PageRouteInfo>? children,
  }) : super(
         ReaderRoute.name,
         args: ReaderRouteArgs(key: key, chapter: chapter),
         initialChildren: children,
       );

  static const String name = 'ReaderRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ReaderRouteArgs>(
        orElse: () => const ReaderRouteArgs(),
      );
      return ReaderPage(key: args.key, chapter: args.chapter);
    },
  );
}

class ReaderRouteArgs {
  const ReaderRouteArgs({this.key, this.chapter});

  final Key? key;

  final ExtractedChapter? chapter;

  @override
  String toString() {
    return 'ReaderRouteArgs{key: $key, chapter: $chapter}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ReaderRouteArgs) return false;
    return key == other.key && chapter == other.chapter;
  }

  @override
  int get hashCode => key.hashCode ^ chapter.hashCode;
}

/// generated route for
/// [ScraperPage]
class ScraperRoute extends PageRouteInfo<void> {
  const ScraperRoute({List<PageRouteInfo>? children})
    : super(ScraperRoute.name, initialChildren: children);

  static const String name = 'ScraperRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const ScraperPage();
    },
  );
}

/// generated route for
/// [SettingsPage]
class SettingsRoute extends PageRouteInfo<void> {
  const SettingsRoute({List<PageRouteInfo>? children})
    : super(SettingsRoute.name, initialChildren: children);

  static const String name = 'SettingsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const SettingsPage();
    },
  );
}

/// generated route for
/// [SplashPage]
class SplashRoute extends PageRouteInfo<void> {
  const SplashRoute({List<PageRouteInfo>? children})
    : super(SplashRoute.name, initialChildren: children);

  static const String name = 'SplashRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const SplashPage();
    },
  );
}

/// generated route for
/// [TranslationPage]
class TranslationRoute extends PageRouteInfo<void> {
  const TranslationRoute({List<PageRouteInfo>? children})
    : super(TranslationRoute.name, initialChildren: children);

  static const String name = 'TranslationRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const TranslationPage();
    },
  );
}
