import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../scraper/domain/models/extracted_chapter.dart';
import '../../../scraper/presentation/providers/scraper_providers.dart';

final novelImportControllerProvider =
    NotifierProvider<NovelImportController,
        AsyncValue<ExtractedChapter?>>(
  NovelImportController.new,
);

class NovelImportController
    extends Notifier<AsyncValue<ExtractedChapter?>> {
  @override
  AsyncValue<ExtractedChapter?> build() {
    return const AsyncData(null);
  }

  Future<void> extractChapter(String url) async {
    state = const AsyncLoading();

    try {
      final repository = ref.read(
        scraperRepositoryProvider,
      );

      final chapter =
          await repository.extractChapter(url);

      state = AsyncData(chapter);
    } catch (error, stackTrace) {
      state = AsyncError(
        error,
        stackTrace,
      );
    }
  }

  void reset() {
    state = const AsyncData(null);
  }
}
