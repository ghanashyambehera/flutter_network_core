import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../adapters/logger/debug_print_logger.dart';
import '../adapters/logger/network_logger.dart';
import '../auth/token_refresh_delegate.dart';
import '../auth/token_storage.dart';
import '../config/network_config.dart';
import '../connectivity/connectivity_checker.dart';
import '../interceptors/auth_interceptor.dart';
import '../interceptors/connectivity_interceptor.dart';
import '../interceptors/logging_interceptor.dart';
import '../interceptors/refresh_interceptor.dart';
import '../interceptors/retry_interceptor.dart';

class DioFactory {
  const DioFactory();

  Dio create({
    required NetworkConfig config,
    required ConnectivityChecker connectivity,
    required TokenStorage storage,
    required bool authenticated,
    TokenRefreshDelegate? refreshDelegate,
    void Function()? onSessionExpired,
    NetworkLogger? logger,
    HttpClientAdapter? httpClientAdapter,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: config.baseUrl,
        connectTimeout: config.connectTimeout,
        sendTimeout: config.sendTimeout,
        receiveTimeout: config.receiveTimeout,
        headers: config.defaultHeaders,
        validateStatus: (status) => status != null && status >= 200 && status < 300,
      ),
    );
    if (httpClientAdapter != null) {
      dio.httpClientAdapter = httpClientAdapter;
    }

    final resolvedLogger = logger ?? const DebugPrintLogger();
    final loggingEnabled = config.enableLogging ?? kDebugMode;
    if (config.sha256Pins.isNotEmpty && kIsWeb) {
      resolvedLogger.log(
        'NetworkConfig.sha256Pins is ignored on web (TLS pinning is unsupported).',
      );
    }

    // Request FIFO / error LIFO: add retry before refresh so 401 is
    // handled by refresh first on the error path.
    dio.interceptors.add(
      ConnectivityInterceptor(checker: connectivity, config: config),
    );
    if (authenticated) {
      dio.interceptors.add(AuthInterceptor(storage: storage, config: config));
    }
    dio.interceptors.add(RetryInterceptor(dio: dio, config: config));
    if (authenticated) {
      dio.interceptors.add(
        RefreshInterceptor(
          dio: dio,
          storage: storage,
          config: config,
          refreshDelegate: refreshDelegate,
          onSessionExpired: onSessionExpired,
        ),
      );
    }
    if (loggingEnabled) {
      dio.interceptors.add(
        LoggingInterceptor(logger: resolvedLogger, config: config),
      );
    }
    dio.interceptors.addAll(config.extraDioInterceptors);
    return dio;
  }
}
