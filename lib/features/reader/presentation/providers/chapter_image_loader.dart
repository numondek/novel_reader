import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../scraper/presentation/providers/scraper_providers.dart';

/// Downloads one chapter picture for display.
///
/// Chapter sites check the `Referer` and browser user agent before
/// serving their images, so a bare Flutter network request comes back
/// empty; pictures already fetched this session are kept in memory.
class ChapterImageLoader {
  ChapterImageLoader(this._dioClient);

  final DioClient _dioClient;
  final Map<String, Uint8List> _cache = <String, Uint8List>{};

  Future<Uint8List> load(String url, {String? referer}) {
    final cached = _cache[url];

    if (cached != null) {
      return Future<Uint8List>.value(cached);
    }

    return _fetch(url, referer);
  }

  Future<Uint8List> _fetch(String url, String? referer) async {
    final uri = Uri.tryParse(url);

    if (uri == null || !uri.hasScheme) {
      throw const PageFetchException('Invalid image URL.');
    }

    try {
      final response = await _dioClient.dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'User-Agent': DioClient.desktopUserAgent,
            'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
            if (referer != null) 'Referer': referer,
          },
        ),
      );

      final bytes = response.data;

      if (bytes == null || bytes.isEmpty) {
        throw const PageFetchException('The image was empty.');
      }

      final picture = Uint8List.fromList(bytes);
      _cache[url] = picture;

      return picture;
    } on DioException catch (error) {
      throw PageFetchException(
        DioClient.friendlyMessage(error),
        statusCode: error.response?.statusCode,
      );
    }
  }
}

final chapterImageLoaderProvider = Provider<ChapterImageLoader>((ref) {
  return ChapterImageLoader(ref.read(dioClientProvider));
});
