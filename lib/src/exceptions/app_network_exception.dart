sealed class AppNetworkException implements Exception {
  const AppNetworkException({
    required this.message,
    this.statusCode,
    this.requestPath,
    this.cause,
  });

  final String message;
  final int? statusCode;
  final String? requestPath;
  final Object? cause;

  @override
  String toString() {
    final code = statusCode == null ? '' : ' ($statusCode)';
    final path = requestPath == null ? '' : ' [$requestPath]';
    return '$runtimeType$code$path: $message';
  }
}

/// Offline, DNS, socket, or connection failure.
final class NetworkException extends AppNetworkException {
  const NetworkException({
    super.message = 'No network connection.',
    super.statusCode,
    super.requestPath,
    super.cause,
  });
}

/// Connect / send / receive timeout (lagging).
final class NetworkTimeoutException extends AppNetworkException {
  const NetworkTimeoutException({
    super.message = 'The request timed out.',
    super.statusCode,
    super.requestPath,
    super.cause,
  });
}

/// 401 on a public call (wrong credentials), not an expired session.
final class AuthenticationException extends AppNetworkException {
  const AuthenticationException({
    super.message = 'Authentication failed.',
    super.statusCode = 401,
    super.requestPath,
    super.cause,
  });
}

/// HTTP 403.
final class AuthorizationException extends AppNetworkException {
  const AuthorizationException({
    super.message = 'You are not allowed to perform this action.',
    super.statusCode = 403,
    super.requestPath,
    super.cause,
  });
}

/// Refresh failed or unrecoverable 401 on a protected call.
final class SessionExpiredException extends AppNetworkException {
  const SessionExpiredException({
    super.message = 'Session expired. Please sign in again.',
    super.statusCode = 401,
    super.requestPath,
    super.cause,
  });
}

/// HTTP 5xx.
final class ServerException extends AppNetworkException {
  const ServerException({
    super.message = 'The server returned an error.',
    super.statusCode,
    super.requestPath,
    super.cause,
  });
}

/// Other 4xx (400, 404, 409, 422, …).
final class ClientException extends AppNetworkException {
  const ClientException({
    super.message = 'The request was rejected.',
    super.statusCode,
    super.requestPath,
    super.cause,
  });
}

/// [CancelToken] cancelled the request.
final class CancelledException extends AppNetworkException {
  const CancelledException({
    super.message = 'The request was cancelled.',
    super.statusCode,
    super.requestPath,
    super.cause,
  });
}
