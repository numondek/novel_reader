/// Keeps chapter pictures on the device so a manhwa chapter stays
/// readable without a network connection.
abstract interface class OfflineImageStore {
  /// Stores the image at [url] on disk and returns its local path,
  /// downloading it the first time it is requested.
  ///
  /// [referer] is the page that embeds the image, sent along for
  /// sites that block hotlinking.
  Future<String> save(String url, {String? referer});
}
