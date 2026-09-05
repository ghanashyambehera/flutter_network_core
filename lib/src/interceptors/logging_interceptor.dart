import 'dart:convert';

import 'package:dio/dio.dart';

import '../adapters/logger/network_logger.dart';
import '../config/network_config.dart';

class LoggingInterceptor extends Interceptor {
  LoggingInterceptor({
    required this.logger,
    required this.config,
  });

  final NetworkLogger logger;
  final NetworkConfig config;

  static const _redactedHeaders = {
    'authorization',
    'cookie',
    'set-cookie',
    'x-api-key',
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    logger.log(
      '→ ${options.method} ${options.uri}\n'
      '  headers: ${_redactMap(options.headers)}\n'
      '  data: ${_redactBody(options.data)}',
    );
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    logger.log(
      '← ${response.statusCode} ${response.requestOptions.uri}\n'
      '  data: ${_redactBody(response.data)}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    logger.log(
      '✖ ${err.type} ${err.requestOptions.uri} '
      '(${err.response?.statusCode})',
    );
    handler.next(err);
  }

  Map<String, dynamic> _redactMap(Map<String, dynamic> input) {
    return input.map((key, value) {
      if (_redactedHeaders.contains(key.toLowerCase()) ||
          key.toLowerCase() == config.authHeaderName.toLowerCase()) {
        return MapEntry(key, '***');
      }
      return MapEntry(key, value);
    });
  }

  String _redactBody(Object? data) {
    if (data == null) {
      return 'null';
    }
    if (data is FormData) {
      return 'FormData(${data.fields.length} fields, ${data.files.length} files)';
    }
    Object? decoded = data;
    if (data is String) {
      try {
        decoded = jsonDecode(data);
      } catch (_) {
        return data;
      }
    }
    if (decoded is Map) {
      final copy = Map<String, dynamic>.from(decoded);
      for (final key in [...copy.keys]) {
        final lower = key.toLowerCase();
        if (lower.contains('token') ||
            lower.contains('password') ||
            lower.contains('secret')) {
          copy[key] = '***';
        }
      }
      return jsonEncode(copy);
    }
    return data.toString();
  }
}
