import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/extensions/time_extensions.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/order_toggle_button.dart';
import '../../../prefetch/presentation/providers/offline_chapter_store_provider.dart';
import '../../../prefetch/presentation/providers/offline_chapters_provider.dart';
import '../../../prefetch/presentation/providers/prefetch_controller_provider.dart';
import '../../../prefetch/presentation/widgets/offline_chapters_sheet.dart';
import '../../../scraper/data/services/chapter_order.dart';
import '../../domain/models/read_novel.dart';
import '../providers/read_novels_provider.dart';

@RoutePage()
class NovelsPage extends ConsumerStatefulWidget {
  const NovelsPage({super.key});

  @override
  ConsumerState<NovelsPage> createState() => _NovelsPageState();
}

class _NovelsPageState extends ConsumerState<NovelsPage> {
  /// Read history is stored most-recent-first, so the list starts
  /// descending and the button flips it to oldest-first.
  var _descending = true;

  /// Drops the novel and everything kept for it: the offline
  /// chapters go too, so a deleted novel leaves neither an entry
  /// nothing shows nor files nothing reads.
  Future<void> _delete(ReadNovel entry) async {
    await ref.read(readNovelsProvider.notifier).remove(entry.key);
    await ref.read(offlineChapterStoreProvider).remove(entry.key);

    // The list, the offline sheet and the prefetch picker all read
    // what is on disk — keep them honest about the purge.
    ref.invalidate(offlineChapterCountsProvider);
    ref.invalidate(offlineChaptersProvider(entry.key));
    ref.invalidate(prefetchControllerProvider(entry.key));
  }

  @override
  Widget build(BuildContext context) {
    final novels = ref.watch(novelHistoryProvider);
    final counts =
        ref.watch(offlineChapterCountsProvider).valueOrNull ??
        const <String, int>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Novels'),
        actions: [
          OrderToggleButton(
            descending: _descending,
            onToggle: () => setState(() => _descending = !_descending),
          ),
        ],
      ),
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

          final ordered = _descending ? entries : entries.reversed.toList();

          return ListView.separated(
            itemCount: ordered.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = ordered[index];
              final hasNovelName = entry.novelTitle != null;
              final offlineCount = counts[entry.key] ?? 0;
              final percent = entry.readPercent(entry.url);

              final subtitle = [
                if (hasNovelName)
                  chapterLabelOf(entry.displayChapterTitle, entry.url),
                if (percent != null) '$percent read',
                entry.host,
                entry.readAt.relativeTime,
                if (offlineCount > 0) '$offlineCount offline',
              ].join(' · ');

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
                      onPressed: () => _delete(entry),
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
