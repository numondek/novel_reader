import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../data/repositories/scraper_repository.dart';
import '../../data/services/adapter_registry.dart';
import '../../data/services/czbooks_novel_adapter.dart';
import '../../data/services/freewebnovel_adapter.dart';
import '../../data/services/generic_novel_adapter.dart';
import '../../data/services/inapp_webview_html_fetcher.dart';
import '../../data/services/sitea_novel_adapter.dart';
import '../../data/services/siteb_novel_adapter.dart';
import '../../data/services/sitec_novel_adapter.dart';
import '../../data/services/sited_novel_adapter.dart';
import '../../data/services/webview_html_fetcher.dart';
import '../../domain/services/novel_site_adapter.dart';

final dioClientProvider = Provider<DioClient>(
  (ref) {
    return DioClient();
  },
);

final novelSiteAdapterProvider =
    Provider<NovelSiteAdapter>(
  (ref) {
    return AdapterRegistry(
      adapters: const [
        FreeWebNovelAdapter(),
        CzbooksAdapter(),
        SiteAAdapter(),
        SiteBAdapter(),
        SiteCAdapter(),
        SiteDAdapter(),
      ],
      fallback: GenericNovelAdapter(),
    );
  },
);

final webViewHtmlFetcherProvider = Provider<WebViewHtmlFetcher>(
  (ref) {
    return InAppWebViewHtmlFetcher();
  },
);

final scraperRepositoryProvider =
    Provider<ScraperRepository>(
  (ref) {
    return ScraperRepository(
      dioClient: ref.read(dioClientProvider),
      adapter: ref.read(novelSiteAdapterProvider),
      webFetcher: ref.read(webViewHtmlFetcherProvider),
    );
  },
);
