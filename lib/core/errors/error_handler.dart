import 'package:dio/dio.dart';

import 'app_exception.dart';

class AppErrorHandler {
  static AppException from(Object error, [StackTrace? stackTrace]) {
    if (error is AppException) return error;
    if (error is DioException) {
      return AppExceptionNetwork(message: error.message, cause: error);
    }
    if (error is FormatException) {
      return AppExceptionParsing(message: error.message, cause: error);
    }
    return AppExceptionNetwork(message: error.toString(), cause: error);
  }
}
