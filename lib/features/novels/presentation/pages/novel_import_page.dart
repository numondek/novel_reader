import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/router/app_router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../controllers/novel_import_controller.dart';

@RoutePage()
class NovelImportPage extends ConsumerStatefulWidget {
  const NovelImportPage({
    super.key,
    required this.url,
  });

  final String url;

  @override
  ConsumerState<NovelImportPage> createState() =>
      _NovelImportPageState();
}

class _NovelImportPageState
    extends ConsumerState<NovelImportPage> {
  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      ref
          .read(novelImportControllerProvider.notifier)
          .extractChapter(widget.url);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      novelImportControllerProvider,
    );

    ref.listen(
      novelImportControllerProvider,
      (_, next) {
        next.whenOrNull(
          data: (chapter) {
            if (chapter == null) {
              return;
            }

            if (!context.mounted) return;

            context.router.replace(
              ReaderRoute(
                chapter: chapter,
              ),
            );
          },
          error: (error, _) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    error.toString(),
                  ),
                ),
              );
          },
        );
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Chapter'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: state.when(
            loading: () {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text(
                    'Extracting chapter...',
                    style: AppTypography.heading,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Please wait while we read the webpage.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySecondary,
                  ),
                ],
              );
            },
            error: (error, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 56,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Unable to extract chapter',
                    style: AppTypography.heading,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySecondary,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      ref
                          .read(
                            novelImportControllerProvider
                                .notifier,
                          )
                          .extractChapter(widget.url);
                    },
                    child: const Text(
                      'Try Again',
                    ),
                  ),
                ],
              );
            },
            data: (_) {
              return const CircularProgressIndicator();
            },
          ),
        ),
      ),
    );
  }
}
