import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../novels/domain/models/read_novel.dart';
import '../../../novels/presentation/providers/read_novels_provider.dart';
import '../../../scraper/domain/models/extracted_chapter.dart';
import 'offline_chapter_store_provider.dart';

/// Chapters saved on the device for [novelKey], in reading order —
/// the list behind each novel's offline shelf.
final offlineChaptersProvider = FutureProvider.autoDispose
    .family<List<ExtractedChapter>, String>((ref, novelKey) async {
      return ref.read(offlineChapterStoreProvider).load(novelKey);
    });

/// How many chapters each read novel has saved offline, keyed by
/// [ReadNovel.key], so the novels list can flag offline-ready entries
/// without loading every stored chapter.
final offlineChapterCountsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
      final novels = await ref.watch(readNovelsProvider.future);
      final store = ref.read(offlineChapterStoreProvider);

      final counts = <String, int>{};
      for (final novel in novels) {
        counts[novel.key] = await store.count(novel.key);
      }

      return counts;
    });
