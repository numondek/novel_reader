import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/presentation/providers/settings_provider.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class NovelFlowApp extends ConsumerWidget {
  const NovelFlowApp({super.key});

  static final AppRouter _appRouter = AppRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final darkMode = ref.watch(settingsProvider).darkMode;

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'NovelFlow',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      routerConfig: _appRouter.config(),
    );
  }
}
