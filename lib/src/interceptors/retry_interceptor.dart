import 'dart:math';

import 'package:dio/dio.dart';

import '../config/network_config.dart';
import '../config/request_flags.dart';

class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    required this.dio,
    required this.config,
    Random? random,
  }) : _random = random ?? Random();

  final Dio dio;
  final NetworkConfig config;
  final Random _random;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (!_shouldRetry(err)) {
      handler.next(err);
      return;
    }

    final attempt = (err.requestOptions.extra['_fnc_retry'] as int?) ?? 0;
    if (attempt >= config.retry.maxExtraAttempts) {
      handler.next(err);
      return;
    }

    await Future<void>.delayed(_backoff(attempt, err));
    final options = _cloneOptions(err.requestOptions);
    options.extra['_fnc_retry'] = attempt + 1;

    try {
      final response = await dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  bool _shouldRetry(DioException err) {
    if (err.requestOptions.extra[RequestFlags.skipRetry] == true) {
      return false;
    }
    if (err.type == DioExceptionType.cancel) {
      return false;
    }
    final status = err.response?.statusCode;
    if (status == 401 || status == 403) {
      return false;
    }
    if (status != null && config.retry.retryableStatusCodes.contains(status)) {
      return true;
    }
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.transformTimeout ||
        err.type == DioExceptionType.connectionError;
  }

  Duration _backoff(int attempt, DioException err) {
    if (config.retry.respectRetryAfterHeader) {
      final header = err.response?.headers.value('retry-after');
      final seconds = int.tryParse(header ?? '');
      if (seconds != null && seconds > 0) {
        return Duration(seconds: seconds);
      }
    }
    final baseMs = config.retry.initialBackoff.inMilliseconds;
    final exp = baseMs * pow(2, attempt).toInt();
    final jitter = _random.nextInt(max(1, (exp * 0.2).round()));
    return Duration(milliseconds: exp + jitter);
  }

  RequestOptions _cloneOptions(RequestOptions options) {
    final data = options.data;
    return options.copyWith(
      data: data is FormData ? data.clone() : data,
    );
  }
}
