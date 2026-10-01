import 'package:flutter/material.dart';

import 'router/app_router.dart';

class NovelFlowApp extends StatelessWidget {
  const NovelFlowApp({super.key});

  static final AppRouter _appRouter = AppRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'NovelFlow',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C5CE7)),
      ),
      routerConfig: _appRouter.config(),
    );
  }
}
