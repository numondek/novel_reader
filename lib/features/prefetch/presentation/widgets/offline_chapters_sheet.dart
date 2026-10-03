import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/router/app_router.dart';
import '../../../novels/domain/models/read_novel.dart';
import '../../../scraper/domain/models/extracted_chapter.dart';
import '../providers/offline_chapters_provider.dart';

/// Lists the chapters of [novel] saved on the device, so the user
/// can see at a glance what is readable without a network.
void showOfflineChapters(BuildContext context, {required ReadNovel novel}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder:
        (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: OfflineChaptersSheet(novel: novel),
          ),
        ),
  );
}

/// The scrollable contents of [showOfflineChapters]: one row per
/// saved chapter, opening the reader straight from local storage.
class OfflineChaptersSheet extends ConsumerWidget {
  const OfflineChaptersSheet({super.key, required this.novel});

  final ReadNovel novel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapters = ref.watch(offlineChaptersProvider(novel.key));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Text(
            novel.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _chapterList(context, chapters)),
      ],
    );
  }

  Widget _chapterList(
    BuildContext context,
    AsyncValue<List<ExtractedChapter>> chapters,
  ) {
    return chapters.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (list) {
        if (list.isEmpty) {
          return const Center(
            child: Text('No chapters saved for this novel yet.'),
          );
        }

        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final chapter = list[index];
            final title =
                chapter.title.isNotEmpty ? chapter.title : chapter.url;

            return ListTile(
              dense: true,
              leading: const Icon(Icons.check_circle_outline),
              title: Text(title),
              onTap: () {
                Navigator.of(context).pop();
                context.router.push(ReaderRoute(chapter: chapter));
              },
            );
          },
        );
      },
    );
  }
}
