import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/widgets/order_toggle_button.dart';
import '../../../novels/domain/models/read_novel.dart';
import '../../../novels/presentation/providers/read_novels_provider.dart';
import '../../../prefetch/presentation/providers/offline_chapters_provider.dart';
import '../../../prefetch/presentation/providers/prefetch_controller_provider.dart';
import '../../data/services/chapter_order.dart';
import '../../domain/models/extracted_chapter.dart';
import '../../domain/models/manhwa_series.dart';
import '../providers/manhwa_batch_provider.dart';
import '../providers/manhwa_shelf_provider.dart';
import 'manhwa_cover.dart';

/// Shows what a shelf card holds: the chapters already on the
/// device and a button for the next batch of them.
void showManhwaSeries(BuildContext context, {required ManhwaSeries series}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder:
        (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: ManhwaSeriesSheet(series: series),
          ),
        ),
  );
}

/// The scrollable contents of [showManhwaSeries].
class ManhwaSeriesSheet extends ConsumerStatefulWidget {
  const ManhwaSeriesSheet({super.key, required this.series});

  final ManhwaSeries series;

  @override
  ConsumerState<ManhwaSeriesSheet> createState() => _ManhwaSeriesSheetState();
}

class _ManhwaSeriesSheetState extends ConsumerState<ManhwaSeriesSheet> {
  /// Saved chapters are stored in reading order, so the list starts
  /// ascending and the button flips it to last-first.
  var _descending = false;

  ManhwaBatchTarget get _target {
    return ManhwaBatchTarget(
      novelKey: widget.series.novelKey,
      sourceUrl: widget.series.sourceUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    final theme = Theme.of(context);
    final batch = ref.watch(manhwaBatchControllerProvider(target));
    final chapters = ref.watch(offlineChaptersProvider(widget.series.novelKey));
    final history =
        ref.watch(readNovelsProvider).valueOrNull ?? const <ReadNovel>[];
    final entry = readEntryFor(history, widget.series.novelKey);

    ref.listen(manhwaBatchControllerProvider(target), (previous, next) {
      final wasSaving = previous?.isSaving ?? false;

      if (wasSaving && !next.isSaving && mounted) {
        ref.invalidate(offlineChaptersProvider(widget.series.novelKey));
        ref.invalidate(manhwaSavedCountsProvider);
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
          child: Row(
            children: [
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 44,
                  height: 60,
                  child: ManhwaCover(series: widget.series),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.series.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              OrderToggleButton(
                descending: _descending,
                onToggle: () => setState(() => _descending = !_descending),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed:
                    batch.isSaving
                        ? null
                        : () =>
                            ref
                                .read(
                                  manhwaBatchControllerProvider(
                                    target,
                                  ).notifier,
                                )
                                .saveNextBatch(),
                icon:
                    batch.isSaving
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.download_for_offline_outlined),
                label: const Text('Save next $prefetchBatchSize chapters'),
              ),
              if (batch.hasProgress) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value:
                      batch.totalCount == 0
                          ? null
                          : batch.savedCount / batch.totalCount,
                ),
                const SizedBox(height: 6),
                Text(
                  'Saved ${batch.savedCount} of ${batch.totalCount}',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              if (batch.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  batch.error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _chapterList(chapters, theme, entry)),
      ],
    );
  }

  Widget _chapterList(
    AsyncValue<List<ExtractedChapter>> chapters,
    ThemeData theme,
    ReadNovel? entry,
  ) {
    return chapters.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Text(
              'No chapters saved for this manhwa yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
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
            final read = entry != null && entry.hasRead(chapter.url);
            final percent = read ? entry.readPercent(chapter.url) : null;

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
