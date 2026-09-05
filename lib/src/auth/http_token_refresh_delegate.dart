import 'package:dio/dio.dart';

import '../config/request_flags.dart';
import 'token_pair.dart';
import 'token_refresh_delegate.dart';

/// Builds a refresh request on the **plain** Dio instance.
class HttpTokenRefreshDelegate implements TokenRefreshDelegate {
  HttpTokenRefreshDelegate({
    required Dio client,
    required this.path,
    required this.bodyBuilder,
    required this.parser,
    this.method = 'POST',
  }) : _client = client;

  final Dio _client;
  final String path;
  final String method;
  final Map<String, dynamic> Function(String refreshToken) bodyBuilder;
  final TokenPair Function(dynamic data) parser;

  @override
  Future<TokenPair> refresh(String refreshToken) async {
    final response = await _client.request<dynamic>(
      path,
      data: bodyBuilder(refreshToken),
      options: Options(
        method: method,
        extra: const {
          RequestFlags.skipAuth: true,
          RequestFlags.skipRetry: true,
        },
      ),
    );
    return parser(response.data);
  }
}
