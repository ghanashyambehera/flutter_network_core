import 'package:dio/dio.dart';

import 'app_network_exception.dart';

class ExceptionMapper {
  const ExceptionMapper();

  AppNetworkException map(DioException error, {bool isPublic = false}) {
    final existing = error.error;
    if (existing is AppNetworkException) {
      return existing;
    }

    final path = error.requestOptions.uri.path;
    final status = error.response?.statusCode;
    final serverMessage = _serverMessage(error.response?.data);

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return NetworkTimeoutException(
          message: serverMessage ?? 'The request timed out.',
          requestPath: path,
          cause: error,
        );
      case DioExceptionType.connectionError:
        return NetworkException(
          message: serverMessage ?? 'No network connection.',
          requestPath: path,
          cause: error,
        );
      case DioExceptionType.cancel:
        return CancelledException(
          requestPath: path,
          cause: error,
        );
      case DioExceptionType.badCertificate:
        return NetworkException(
          message: serverMessage ?? 'TLS certificate is not trusted.',
          requestPath: path,
          cause: error,
        );
      case DioExceptionType.badResponse:
        return _fromStatus(
          status: status,
          path: path,
          serverMessage: serverMessage,
          cause: error,
          isPublic: isPublic,
        );
      case DioExceptionType.unknown:
        return NetworkException(
          message: serverMessage ?? error.message ?? 'Unexpected network error.',
          requestPath: path,
          cause: error,
        );
    }
  }

  AppNetworkException _fromStatus({
    required int? status,
    required String path,
    required String? serverMessage,
    required Object cause,
    required bool isPublic,
  }) {
    if (status == 401) {
      if (isPublic) {
        return AuthenticationException(
          message: serverMessage ?? 'Authentication failed.',
          requestPath: path,
          cause: cause,
        );
      }
      return SessionExpiredException(
        message: serverMessage ?? 'Session expired. Please sign in again.',
        requestPath: path,
        cause: cause,
      );
    }
    if (status == 403) {
      return AuthorizationException(
        message: serverMessage ?? 'You are not allowed to perform this action.',
        requestPath: path,
        cause: cause,
      );
    }
    if (status != null && status >= 500) {
      return ServerException(
        message: serverMessage ?? 'The server returned an error.',
        statusCode: status,
        requestPath: path,
        cause: cause,
      );
    }
    if (status != null && status >= 400) {
      return ClientException(
        message: serverMessage ?? 'The request was rejected.',
        statusCode: status,
        requestPath: path,
        cause: cause,
      );
    }
    return ServerException(
      message: serverMessage ?? 'Unexpected response.',
      statusCode: status,
      requestPath: path,
      cause: cause,
    );
  }

  static String? _serverMessage(Object? data) {
    if (data == null) {
      return null;
    }
    if (data is String && data.trim().isNotEmpty) {
      return data;
    }
    if (data is Map) {
      for (final key in const ['message', 'error', 'detail', 'title']) {
        final value = data[key];
        if (value is String && value.trim().isNotEmpty) {
          return value;
        }
      }
    }
    return null;
  }
}
