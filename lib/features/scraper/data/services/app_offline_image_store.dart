import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/network/dio_client.dart';
import '../../domain/services/offline_image_store.dart';

/// Downloads chapter pictures into `<documents>/manhwa`, named by a
/// hash of their URL so re-saving an already-stored image is free.
class AppOfflineImageStore implements OfflineImageStore {
  AppOfflineImageStore({required DioClient dioClient}) : _dioClient = dioClient;

  static const String folderName = 'manhwa';

  final DioClient _dioClient;

  @override
  Future<String> save(String url, {String? referer}) async {
    final uri = Uri.tryParse(url);

    if (uri == null || !uri.hasScheme) {
      throw const PageFetchException('Invalid image URL.');
    }

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}$folderName');
    await dir.create(recursive: true);

    final target =
        '${dir.path}${Platform.pathSeparator}${_hash(url)}${_extension(uri)}';

    if (await File(target).exists()) {
      return target;
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

      await File(target).writeAsBytes(bytes, flush: true);

      return target;
    } on DioException catch (error) {
      throw PageFetchException(
        DioClient.friendlyMessage(error),
        statusCode: error.response?.statusCode,
      );
    }
  }

  static const _extensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.avif',
  };

  static String _extension(Uri uri) {
    final path = uri.path.toLowerCase();
    final dot = path.lastIndexOf('.');

    if (dot >= 0) {
      final suffix = path.substring(dot);

      if (_extensions.contains(suffix)) {
        return suffix;
      }
    }

    return '.img';
  }

  /// djb2 over the string's code units: deterministic across runs
  /// and always a safe file name, unlike the raw URL.
  static String _hash(String value) {
    var hash = 5381;

    for (final unit in value.codeUnits) {
      hash = ((hash << 5) + hash + unit) & 0x7FFFFFFF;
    }

    return hash.toRadixString(16);
  }
}
