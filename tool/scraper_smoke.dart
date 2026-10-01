// CLI smoke test for the Dio path only. The WebView fallback runs
// in-app only (no embedded WebView available under `dart run`).
// ignore_for_file: avoid_print
import 'package:novel_reader/core/network/dio_client.dart';
import 'package:novel_reader/features/scraper/data/repositories/scraper_repository.dart';
import 'package:novel_reader/features/scraper/data/services/adapter_registry.dart';
import 'package:novel_reader/features/scraper/data/services/freewebnovel_adapter.dart';
import 'package:novel_reader/features/scraper/data/services/generic_novel_adapter.dart';
import 'package:novel_reader/features/scraper/data/services/sitea_novel_adapter.dart';
import 'package:novel_reader/features/scraper/data/services/siteb_novel_adapter.dart';
import 'package:novel_reader/features/scraper/data/services/sitec_novel_adapter.dart';
import 'package:novel_reader/features/scraper/data/services/sited_novel_adapter.dart';

Future<void> main() async {
  final registry = AdapterRegistry(
    adapters: const [
      FreeWebNovelAdapter(),
      SiteAAdapter(),
      SiteBAdapter(),
      SiteCAdapter(),
      SiteDAdapter(),
    ],
    fallback: GenericNovelAdapter(),
  );

  final repository = ScraperRepository(
    dioClient: DioClient(),
    adapter: registry,
  );

  const url =
      'https://freewebnovel.com/novel/unrivaled-martial-emperor/chapter-58';

  final chapter = await repository.extractChapter(url);

  print('adapter: ${registry.resolve(Uri.parse(url)).runtimeType}');
  print('title: ${chapter.title}');
  print('paragraphs: ${chapter.paragraphs.length}');
  print('first: ${chapter.paragraphs.first}');
  print('next: ${chapter.nextChapterUrl}');
  print('prev: ${chapter.previousChapterUrl}');
}
