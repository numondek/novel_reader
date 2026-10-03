import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/extensions/time_extensions.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../prefetch/presentation/providers/offline_chapters_provider.dart';
import '../../../prefetch/presentation/widgets/offline_chapters_sheet.dart';
import '../providers/read_novels_provider.dart';

@RoutePage()
class NovelsPage extends ConsumerWidget {
  const NovelsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final novels = ref.watch(readNovelsProvider);
    final counts =
        ref.watch(offlineChapterCountsProvider).valueOrNull ??
        const <String, int>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Novels')),
      body: novels.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, _) => EmptyState(
              icon: Icons.error_outline,
              title: 'Could not load novels',
              subtitle: '$error',
            ),
        data: (entries) {
          if (entries.isEmpty) {
            return const EmptyState(
              icon: Icons.menu_book_outlined,
              title: 'No read novels yet',
              subtitle: 'Novels you read will appear here.',
            );
          }

          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final hasNovelName = entry.novelTitle != null;
              final offlineCount = counts[entry.key] ?? 0;

              final offlineSuffix =
                  offlineCount > 0 ? ' · $offlineCount offline' : '';

              final subtitle =
                  hasNovelName
                      ? '${entry.displayChapterTitle} · '
                          '${entry.host} · '
                          '${entry.readAt.relativeTime}$offlineSuffix'
                      : '${entry.host} · '
                          '${entry.readAt.relativeTime}$offlineSuffix';

              return ListTile(
                leading: const CircleAvatar(
                  radius: 20,
                  child: Icon(Icons.menu_book_outlined, size: 20),
                ),
                title: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (offlineCount > 0)
                      IconButton(
                        tooltip: 'Offline chapters',
                        icon: const Icon(Icons.offline_pin),
                        onPressed:
                            () => showOfflineChapters(context, novel: entry),
                      ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed:
                          () => ref
                              .read(readNovelsProvider.notifier)
                              .remove(entry.key),
                    ),
                  ],
                ),
                onTap:
                    () => context.router.push(NovelImportRoute(url: entry.url)),
              );
            },
          );
        },
      ),
    );
  }
}
