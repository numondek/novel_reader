abstract final class AppConstants {
  static const String appName = 'Novel Reader';

  static const Duration cacheTtl = Duration(hours: 6);
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);

  static const int itemsPerPage = 20;
  static const double readerLineHeight = 1.8;
}
