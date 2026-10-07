import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../prefetch/presentation/providers/offline_chapter_store_provider.dart';
import '../../data/repositories/scraper_repository.dart';
import '../../data/services/adapter_registry.dart';
import '../../data/services/app_offline_image_store.dart';
import '../../data/services/comix_novel_adapter.dart';
import '../../data/services/czbooks_novel_adapter.dart';
import '../../data/services/freewebnovel_adapter.dart';
import '../../data/services/generic_novel_adapter.dart';
import '../../data/services/inapp_webview_html_fetcher.dart';
import '../../data/services/novelhi_novel_adapter.dart';
import '../../data/services/sitea_novel_adapter.dart';
import '../../data/services/siteb_novel_adapter.dart';
import '../../data/services/sitec_novel_adapter.dart';
import '../../data/services/sited_novel_adapter.dart';
import '../../data/services/webview_html_fetcher.dart';
import '../../domain/services/novel_site_adapter.dart';
import '../../domain/services/offline_image_store.dart';

final dioClientProvider = Provider<DioClient>((ref) {
  return DioClient();
});

final novelSiteAdapterProvider = Provider<NovelSiteAdapter>((ref) {
  return AdapterRegistry(
    adapters: [
      NovelhiAdapter(),
      ComixAdapter(),
      const FreeWebNovelAdapter(),
      const CzbooksAdapter(),
      const SiteAAdapter(),
      const SiteBAdapter(),
      const SiteCAdapter(),
      const SiteDAdapter(),
    ],
    fallback: GenericNovelAdapter(),
  );
});

final webViewHtmlFetcherProvider = Provider<WebViewHtmlFetcher>((ref) {
  return InAppWebViewHtmlFetcher();
});

final scraperRepositoryProvider = Provider<ScraperRepository>((ref) {
  return ScraperRepository(
    dioClient: ref.read(dioClientProvider),
    adapter: ref.read(novelSiteAdapterProvider),
    webFetcher: ref.read(webViewHtmlFetcherProvider),
    offline: ref.read(offlineChapterStoreProvider),
  );
});

/// Cover art for the manhwa shelf, downloaded beside the chapter
/// pictures it already shares a folder with.
final offlineImageStoreProvider = Provider<OfflineImageStore>((ref) {
  return AppOfflineImageStore(dioClient: ref.read(dioClientProvider));
});
