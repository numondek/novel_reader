import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/widgets/empty_state.dart';
import '../providers/read_novels_provider.dart';

@RoutePage()
class NovelsPage extends ConsumerWidget {
  const NovelsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final novels = ref.watch(readNovelsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Novels')),
      body: novels.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, _) => EmptyState(
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

              final subtitle = hasNovelName
                  ? '${entry.displayChapterTitle} · '
                      '${entry.host} · '
                      '${_relativeTime(entry.readAt)}'
                  : '${entry.host} · ${_relativeTime(entry.readAt)}';

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
                trailing: IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => ref
                      .read(readNovelsProvider.notifier)
                      .remove(entry.key),
                ),
                onTap: () => context.router.push(
                  NovelImportRoute(url: entry.url),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

String _relativeTime(DateTime time) {
  final difference = DateTime.now().difference(time);

  if (difference.inMinutes < 1) {
    return 'Just now';
  }

  if (difference.inHours < 1) {
    return '${difference.inMinutes} min ago';
  }

  if (difference.inDays < 1) {
    return '${difference.inHours} h ago';
  }

  if (difference.inDays < 30) {
    return '${difference.inDays} d ago';
  }

  return '${time.year}-'
      '${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';
}
