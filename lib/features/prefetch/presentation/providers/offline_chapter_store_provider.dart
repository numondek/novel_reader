import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../scraper/data/services/app_offline_image_store.dart';
import '../../../scraper/domain/services/offline_chapter_store.dart';
import '../../data/services/app_database_offline_chapter_store.dart';

/// The device's saved-chapter storage, filled by the prefetch page
/// and read by the scraper to keep saved chapters available
/// offline.
final offlineChapterStoreProvider = Provider<OfflineChapterStore>((ref) {
  return AppDatabaseOfflineChapterStore(
    images: AppOfflineImageStore(dioClient: DioClient()),
  );
});
