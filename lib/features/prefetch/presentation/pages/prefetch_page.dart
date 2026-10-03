import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/empty_state.dart';
import '../../../novels/domain/models/read_novel.dart';
import '../../../novels/presentation/providers/read_novels_provider.dart';
import '../providers/offline_chapters_provider.dart';
import '../providers/prefetch_controller_provider.dart';

@RoutePage()
class PrefetchPage extends ConsumerStatefulWidget {
  const PrefetchPage({super.key});

  @override
  ConsumerState<PrefetchPage> createState() => _PrefetchPageState();
}

class _PrefetchPageState extends ConsumerState<PrefetchPage> {
  /// Which novel to prefetch; defaults to the most recently read.
  String? _novelKey;

  @override
  Widget build(BuildContext context) {
    final novels = ref.watch(readNovelsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Prefetch')),
      body: novels.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, stackTrace) => EmptyState(
              icon: Icons.download_for_offline_outlined,
              title: 'Could not list novels',
              subtitle: '$error',
            ),
        data: (entries) => _buildNovels(context, entries),
      ),
    );
  }

  Widget _buildNovels(BuildContext context, List<ReadNovel> novels) {
    if (novels.isEmpty) {
      return const EmptyState(
        icon: Icons.download_for_offline_outlined,
        title: 'Nothing to prefetch yet',
        subtitle:
            'Open a chapter first, then come back to save chapters '
            'for offline reading.',
      );
    }

    final selected = _selectNovel(novels);
    final controllerKey = prefetchControllerProvider(selected.key);
    final state = ref.watch(controllerKey);
    final theme = Theme.of(context);

    ref.listen<PrefetchState>(controllerKey, (previous, next) {
      if (next.savedCount != previous?.savedCount) {
        // The novels list shows offline counts; keep them honest.
        ref.invalidate(offlineChapterCountsProvider);
      }

      final error = next.error;

      if (error != null && error != previous?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    });

    final canFetch = state.ready && !state.isFetching && state.hasNextBatch;
    final finished = state.hasSaved && !state.hasNextBatch;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (novels.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: DropdownButtonFormField<String>(
              value: selected.key,
              decoration: const InputDecoration(labelText: 'Novel'),
              items: [
                for (final novel in novels)
                  DropdownMenuItem<String>(
                    value: novel.key,
                    child: Text(novel.title, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (key) {
                if (key == null) return;
                setState(() => _novelKey = key);
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            state.hasSaved
                ? '${state.savedCount} chapters saved offline'
                : 'No chapters saved yet',
            style: theme.textTheme.titleMedium,
          ),
        ),
        if (state.isFetching) ...[
          LinearProgressIndicator(
            value: state.fetchedCount / prefetchBatchSize,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Saved ${state.fetchedCount} of $prefetchBatchSize',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.all(16),
          child:
              finished
                  ? Text(
                    'Every chapter is saved.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  )
                  : FilledButton.icon(
                    onPressed:
                        canFetch
                            ? () =>
                                ref
                                    .read(controllerKey.notifier)
                                    .fetchNextBatch()
                            : null,
                    icon:
                        state.isFetching
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.download_for_offline_outlined),
                    label: Text(
                      state.isFetching ? 'Saving…' : state.buttonLabel,
                    ),
                  ),
        ),
        const Divider(height: 1),
        Expanded(child: _savedList(state)),
      ],
    );
  }

  Widget _savedList(PrefetchState state) {
    if (!state.ready) {
      return const Center(child: CircularProgressIndicator());
    }

    final titles = state.savedTitles;
    if (titles.isEmpty) {
      return const Center(child: Text('Chapters you save show up here.'));
    }

    return ListView.separated(
      itemCount: titles.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        return ListTile(
          dense: true,
          leading: const Icon(Icons.check_circle_outline),
          title: Text(titles[index]),
        );
      },
    );
  }

  ReadNovel _selectNovel(List<ReadNovel> novels) {
    final key = _novelKey;

    if (key != null) {
      for (final novel in novels) {
        if (novel.key == key) return novel;
      }
    }

    return novels.first;
  }
}
