import 'package:dio/dio.dart';

import '../auth/token_storage.dart';
import '../config/network_config.dart';
import '../config/request_flags.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.storage,
    required this.config,
  });

  final TokenStorage storage;
  final NetworkConfig config;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[RequestFlags.skipAuth] == true ||
        config.isPublicPath(options.path) ||
        config.isPublicPath(options.uri.path)) {
      handler.next(options);
      return;
    }

    final pair = await storage.read();
    final token = pair?.accessToken;
    if (token != null && token.isNotEmpty) {
      options.headers[config.authHeaderName] = config.authHeaderBuilder(token);
    }
    handler.next(options);
  }
}
