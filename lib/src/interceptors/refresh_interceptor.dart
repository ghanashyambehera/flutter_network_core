import 'package:dio/dio.dart';

import '../auth/token_refresh_delegate.dart';
import '../auth/token_storage.dart';
import '../config/network_config.dart';
import '../config/request_flags.dart';
import '../exceptions/app_network_exception.dart';

class RefreshInterceptor extends QueuedInterceptor {
  RefreshInterceptor({
    required this.dio,
    required this.storage,
    required this.config,
    this.refreshDelegate,
    this.onSessionExpired,
  });

  final Dio dio;
  final TokenStorage storage;
  final NetworkConfig config;
  final TokenRefreshDelegate? refreshDelegate;
  final void Function()? onSessionExpired;

  bool _expiryNotified = false;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (!_isRecoverableUnauthorized(err)) {
      handler.next(err);
      return;
    }

    if (err.requestOptions.extra[RequestFlags.refreshRetry] == true) {
      await _expire(err.requestOptions.uri.path);
      handler.next(_sessionExpired(err));
      return;
    }

    final current = await storage.read();
    final sent = err.requestOptions.headers[config.authHeaderName]?.toString();
    final latestHeader = current == null || current.accessToken.isEmpty
        ? null
        : config.authHeaderBuilder(current.accessToken);

    // Another queued 401 already refreshed. Retry with the new token only.
    if (latestHeader != null && latestHeader != sent) {
      await _retry(err, handler);
      return;
    }

    final delegate = refreshDelegate;
    if (delegate == null) {
      await _expire(err.requestOptions.uri.path);
      handler.next(_sessionExpired(err));
      return;
    }

    final refreshToken = current?.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      await _expire(err.requestOptions.uri.path);
      handler.next(_sessionExpired(err));
      return;
    }

    try {
      final pair = await delegate.refresh(refreshToken);
      await storage.write(pair);
      _expiryNotified = false;
    } catch (error) {
      await _expire(err.requestOptions.uri.path);
      handler.next(_sessionExpired(err, cause: error));
      return;
    }

    await _retry(err, handler);
  }

  Future<void> _retry(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      final options = _retryOptions(err.requestOptions);
      final pair = await storage.read();
      if (pair != null && pair.accessToken.isNotEmpty) {
        options.headers[config.authHeaderName] =
            config.authHeaderBuilder(pair.accessToken);
      }
      final retried = await dio.fetch<dynamic>(options);
      handler.resolve(retried);
    } on DioException catch (retryError) {
      if (retryError.response?.statusCode == 401) {
        await _expire(err.requestOptions.uri.path);
        handler.next(_sessionExpired(retryError));
        return;
      }
      handler.next(retryError);
    }
  }

  bool _isRecoverableUnauthorized(DioException err) {
    if (err.response?.statusCode != 401) {
      return false;
    }
    if (err.requestOptions.extra[RequestFlags.skipAuth] == true) {
      return false;
    }
    final path = err.requestOptions.path;
    final uriPath = err.requestOptions.uri.path;
    if (config.isPublicPath(path) || config.isPublicPath(uriPath)) {
      return false;
    }
    return true;
  }

  RequestOptions _retryOptions(RequestOptions options) {
    final extra = Map<String, dynamic>.from(options.extra)
      ..[RequestFlags.refreshRetry] = true;
    final data = options.data;
    return options.copyWith(
      extra: extra,
      data: data is FormData ? data.clone() : data,
    );
  }

  Future<void> _expire(String path) async {
    await storage.clear();
    if (!_expiryNotified) {
      _expiryNotified = true;
      onSessionExpired?.call();
    }
  }

  DioException _sessionExpired(DioException err, {Object? cause}) {
    return DioException(
      requestOptions: err.requestOptions,
      response: err.response,
      type: err.type,
      error: SessionExpiredException(
        requestPath: err.requestOptions.uri.path,
        cause: cause ?? err,
      ),
    );
  }
}
