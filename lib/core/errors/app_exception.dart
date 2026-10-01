sealed class AppException implements Exception {
  const AppException({this.message, this.cause});

  final String? message;
  final Object? cause;

  String get prettyMessage => message ?? runtimeType.toString();

  @override
  String toString() => '$runtimeType: ${message ?? cause ?? ''}';
}

class AppExceptionNetwork extends AppException {
  const AppExceptionNetwork({super.message, super.cause});
}

class AppExceptionParsing extends AppException {
  const AppExceptionParsing({super.message, super.cause});
}

class AppExceptionStorage extends AppException {
  const AppExceptionStorage({super.message, super.cause});
}

class AppExceptionNotFound extends AppException {
  const AppExceptionNotFound({super.message, super.cause});
}

class AppExceptionScraping extends AppException {
  const AppExceptionScraping({super.message, super.cause});
}
