import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/widgets/order_toggle_button.dart';
import '../../../novels/domain/models/read_novel.dart';
import '../../../scraper/data/services/chapter_order.dart';
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
class OfflineChaptersSheet extends ConsumerStatefulWidget {
  const OfflineChaptersSheet({super.key, required this.novel});

  final ReadNovel novel;

  @override
  ConsumerState<OfflineChaptersSheet> createState() =>
      _OfflineChaptersSheetState();
}

class _OfflineChaptersSheetState extends ConsumerState<OfflineChaptersSheet> {
  /// Saved chapters are stored in reading order, so the list starts
  /// ascending and the button flips it to last-first.
  var _descending = false;

  @override
  Widget build(BuildContext context) {
    final chapters = ref.watch(offlineChaptersProvider(widget.novel.key));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
          child: Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.novel.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              OrderToggleButton(
                descending: _descending,
                onToggle: () => setState(() => _descending = !_descending),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _chapterList(chapters)),
      ],
    );
  }

  Widget _chapterList(AsyncValue<List<ExtractedChapter>> chapters) {
    return chapters.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (list) {
        if (list.isEmpty) {
          return const Center(
            child: Text('No chapters saved for this novel yet.'),
          );
        }

        final ordered = _descending ? list.reversed.toList() : list;

        return ListView.separated(
          itemCount: ordered.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final chapter = ordered[index];
            final title =
                chapter.title.isNotEmpty ? chapter.title : chapter.url;
            final read = widget.novel.hasRead(chapter.url);
            final percent = read ? widget.novel.readPercent(chapter.url) : null;
            final theme = Theme.of(context);

            return ListTile(
              dense: true,
              leading: Icon(
                read ? Icons.check_circle : Icons.check_circle_outline,
                color:
                    read
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
              ),
              title: Text(chapterLabelOf(title, chapter.url)),
              subtitle:
                  !read
                      ? null
                      : Text(
                        percent == null ? 'Read' : '$percent read',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
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
