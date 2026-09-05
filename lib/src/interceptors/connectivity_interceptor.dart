import 'package:dio/dio.dart';

import '../config/network_config.dart';
import '../config/request_flags.dart';
import '../connectivity/connectivity_checker.dart';
import '../exceptions/app_network_exception.dart';

class ConnectivityInterceptor extends Interceptor {
  ConnectivityInterceptor({
    required this.checker,
    required this.config,
    Dio? reachabilityClient,
  }) : _reachabilityClient = reachabilityClient;

  final ConnectivityChecker checker;
  final NetworkConfig config;
  final Dio? _reachabilityClient;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[RequestFlags.skipConnectivity] == true) {
      handler.next(options);
      return;
    }

    final online = await checker.isOnline;
    if (!online) {
      handler.reject(_offline(options));
      return;
    }

    final probe = config.reachabilityUrl;
    if (probe != null && probe.isNotEmpty && _reachabilityClient != null) {
      try {
        await _reachabilityClient.head<void>(
          probe,
          options: Options(
            extra: const {RequestFlags.skipConnectivity: true},
          ),
        );
      } on DioException {
        handler.reject(_offline(options));
        return;
      }
    }

    handler.next(options);
  }

  DioException _offline(RequestOptions options) {
    return DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: NetworkException(
        requestPath: options.uri.path,
      ),
    );
  }
}
