import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../features/audio/presentation/pages/audio_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/library/presentation/pages/library_page.dart';
import '../../features/novels/presentation/pages/novel_import_page.dart';
import '../../features/novels/presentation/pages/novels_page.dart';
import '../../features/prefetch/presentation/pages/prefetch_page.dart';
import '../../features/reader/presentation/pages/reader_page.dart';
import '../../features/scraper/domain/models/extracted_chapter.dart';
import '../../features/scraper/presentation/pages/scraper_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/splash/presentation/pages/splash_page.dart';
import '../../features/translation/presentation/pages/translation_page.dart';

part 'app_router.gr.dart';

@AutoRouterConfig(replaceInRouteName: 'Page,Route')
class AppRouter extends RootStackRouter {
  @override
  RouteType get defaultRouteType => const RouteType.material();

  @override
  List<AutoRoute> get routes => [
        AutoRoute(page: SplashRoute.page, initial: true),
        AutoRoute(page: HomeRoute.page),
        AutoRoute(page: NovelImportRoute.page),
        AutoRoute(page: NovelsRoute.page),
        AutoRoute(page: ScraperRoute.page),
        AutoRoute(page: TranslationRoute.page),
        AutoRoute(page: ReaderRoute.page),
        AutoRoute(page: AudioRoute.page),
        AutoRoute(page: PrefetchRoute.page),
        AutoRoute(page: LibraryRoute.page),
        AutoRoute(page: SettingsRoute.page),
      ];
}
