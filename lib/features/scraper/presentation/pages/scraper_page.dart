import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../novels/domain/models/read_novel.dart';
import '../../../novels/presentation/providers/read_novels_provider.dart';
import '../../../prefetch/presentation/providers/offline_chapter_store_provider.dart';
import '../../../prefetch/presentation/providers/offline_chapters_provider.dart';
import '../../data/services/chapter_order.dart';
import '../../domain/models/manhwa_series.dart';
import '../providers/manhwa_shelf_provider.dart';
import '../providers/scraper_controller_provider.dart';
import '../widgets/manhwa_cover.dart';
import '../widgets/manhwa_series_sheet.dart';

/// Opens a series or contents page, lists its chapters and keeps
/// them — pictures included — on the device for offline reading.
///
/// With nothing open it shows a shelf of everything the user has
/// read before, as covers.
@RoutePage()
class ScraperPage extends ConsumerStatefulWidget {
  const ScraperPage({super.key});

  @override
  ConsumerState<ScraperPage> createState() => _ScraperPageState();
}

class _ScraperPageState extends ConsumerState<ScraperPage> {
  final TextEditingController _urlController = TextEditingController();

  /// Whether a shelf card's resume button is fetching its chapter.
  var _resuming = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scraperControllerProvider);
    final theme = Theme.of(context);

    ref.listen(scraperControllerProvider, (previous, next) {
      final error = next.error;

      if (error != null && error != previous?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Manhwa')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Series or chapter URL',
                hintText: 'https://example.com/series/…',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _open(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: state.isLoading || state.isSavingAll ? null : _open,
              icon:
                  state.isLoading
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.travel_explore_outlined),
              label: Text(state.isLoading ? 'Opening…' : 'Open'),
            ),
          ),
          if (state.isLoading) const LinearProgressIndicator(),
          if (state.hasChapters) _header(state, theme),
          Expanded(child: _body(state, theme)),
        ],
      ),
    );
  }

  void _open() {
    ref.read(scraperControllerProvider.notifier).open(_urlController.text);
  }

  void _close() {
    ref.read(scraperControllerProvider.notifier).close();
  }

  Widget _header(ScraperState state, ThemeData theme) {
    final busy = state.isSavingAll;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: _close,
            tooltip: 'My manhwa',
            icon: const Icon(Icons.grid_view_outlined),
          ),
          Expanded(
            child: Text(
              busy
                  ? 'Saving ${state.savedCount} of ${state.totalCount}…'
                  : '${state.chapters.length} chapters · '
                      '${state.savedTotal} saved',
              style: theme.textTheme.titleSmall,
            ),
          ),
          if (!busy)
            TextButton(
              onPressed:
                  state.savedTotal == state.chapters.length
                      ? null
                      : () =>
                          ref
                              .read(scraperControllerProvider.notifier)
                              .saveAll(),
              child: const Text('Save all'),
            ),
        ],
      ),
    );
  }

  Widget _body(ScraperState state, ThemeData theme) {
    if (state.hasChapters) {
      return _chapterList(state, theme);
    }

    final shelf =
        ref.watch(manhwaSeriesProvider).valueOrNull ?? const <ManhwaSeries>[];

    if (shelf.isNotEmpty) {
      return _shelf(shelf, theme);
    }

    if (state.error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Could not open the page',
        subtitle: state.error!,
      );
    }

    return const EmptyState(
      icon: Icons.travel_explore_outlined,
      title: 'Read manhwa offline',
      subtitle:
          'Paste the URL of a series or chapter page to list its '
          'chapters, then save them to read without a connection.',
    );
  }

  Widget _chapterList(ScraperState state, ThemeData theme) {
    final entries =
        ref.watch(readNovelsProvider).valueOrNull ?? const <ReadNovel>[];
    final entry =
        state.novelKey.isEmpty ? null : readEntryFor(entries, state.novelKey);

    return ListView.separated(
      itemCount: state.chapters.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final chapter = state.chapters[index];
        final saving = state.savingUrls.contains(chapter.url);
        final read = entry != null && entry.hasRead(chapter.url);
        final percent = read ? entry.readPercent(chapter.url) : null;
        final title = chapter.title.isNotEmpty ? chapter.title : chapter.url;

        return ListTile(
          leading: Icon(
            read ? Icons.check_circle : Icons.radio_button_unchecked,
            color: read ? theme.colorScheme.primary : theme.colorScheme.outline,
          ),
          title: Text(chapterLabelOf(title, chapter.url), maxLines: 2),
          subtitle:
              (chapter.saved || read)
                  ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (chapter.saved)
                        Text('Saved offline', style: theme.textTheme.bodySmall),
                      if (read)
                        Text(
                          percent == null ? 'Read' : '$percent read',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  )
                  : null,
          trailing: _trailing(state, chapter, saving),
          onTap:
              saving || state.savingUrls.isNotEmpty
                  ? null
                  : () => _read(chapter),
        );
      },
    );
  }

  /// The shelf: every manhwa opened before, cover first.
  Widget _shelf(List<ManhwaSeries> series, ThemeData theme) {
    final counts =
        ref.watch(manhwaSavedCountsProvider).valueOrNull ??
        const <String, int>{};
    final history =
        ref.watch(readNovelsProvider).valueOrNull ?? const <ReadNovel>[];

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemCount: series.length,
      itemBuilder: (context, index) {
        final entry = series[index];

        return _card(
          entry,
          theme,
          counts[entry.novelKey] ?? 0,
          readEntryFor(history, entry.novelKey),
        );
      },
    );
  }

  Widget _card(
    ManhwaSeries series,
    ThemeData theme,
    int saved,
    ReadNovel? entry,
  ) {
    final lastUrl = entry?.url ?? '';
    final resumeUrl = lastUrl.isEmpty ? null : lastUrl;
    final percent = entry?.readPercent(lastUrl);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => showManhwaSeries(context, series: series),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ManhwaCover(series: series),
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Material(
                      color: theme.colorScheme.surfaceContainerHighest,
                      shape: const CircleBorder(),
                      elevation: 1,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Delete',
                        onPressed: () => _delete(series),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                  if (resumeUrl != null)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Material(
                        color: theme.colorScheme.surfaceContainerHighest,
                        shape: const CircleBorder(),
                        elevation: 1,
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Resume reading',
                          onPressed:
                              _resuming ? null : () => _resume(resumeUrl),
                          icon:
                              _resuming
                                  ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(Icons.play_arrow),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    series.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    saved > 0 ? '$saved saved' : 'Nothing saved yet',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (percent != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '$percent read',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trailing(ScraperState state, ScrapeChapter chapter, bool saving) {
    if (saving) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (chapter.saved) {
      return Icon(
        Icons.check_circle_outline,
        color: Theme.of(context).colorScheme.primary,
      );
    }

    return IconButton(
      onPressed:
          state.savingUrls.isNotEmpty || state.isSavingAll
              ? null
              : () =>
                  ref.read(scraperControllerProvider.notifier).save(chapter),
      tooltip: 'Save offline',
      icon: const Icon(Icons.download_for_offline_outlined),
    );
  }

  Future<void> _read(ScrapeChapter chapter) async {
    final controller = ref.read(scraperControllerProvider.notifier);
    final extracted = await controller.readChapter(chapter.url);

    if (extracted == null || !mounted) return;

    context.router.push(ReaderRoute(chapter: extracted));
  }

  /// Takes a manhwa off the shelf: its progress and the chapters
  /// saved for it go with it — a card the user deleted must leave
  /// neither entries nor files behind, all of them unreachable now.
  Future<void> _delete(ManhwaSeries series) async {
    await ref.read(manhwaSeriesProvider.notifier).remove(series.novelKey);
    await ref.read(readNovelsProvider.notifier).removeSeries(series.novelKey);
    await ref.read(offlineChapterStoreProvider).remove(series.novelKey);

    ref.invalidate(manhwaSavedCountsProvider);
    ref.invalidate(offlineChaptersProvider(series.novelKey));
  }

  /// Opens the chapter the card's manhwa was left at, straight from
  /// the shelf — no series sheet in between.
  Future<void> _resume(String url) async {
    if (_resuming) return;

    setState(() => _resuming = true);

    final controller = ref.read(scraperControllerProvider.notifier);
    final extracted = await controller.readChapter(url);

    if (!mounted) return;

    setState(() => _resuming = false);

    if (extracted == null) return;

    context.router.push(ReaderRoute(chapter: extracted));
  }
}
