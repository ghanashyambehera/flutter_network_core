import 'package:dio/dio.dart';
import 'package:meta/meta.dart';

typedef AuthHeaderBuilder = String Function(String accessToken);
typedef PathMatcher = bool Function(String path);

@immutable
class RetryConfig {
  const RetryConfig({
    this.maxExtraAttempts = 2,
    this.retryableStatusCodes = const {408, 429, 500, 502, 503, 504},
    this.initialBackoff = const Duration(milliseconds: 300),
    this.respectRetryAfterHeader = true,
  });

  /// Additional tries after the first failure.
  final int maxExtraAttempts;
  final Set<int> retryableStatusCodes;
  final Duration initialBackoff;
  final bool respectRetryAfterHeader;
}

@immutable
class NetworkConfig {
  NetworkConfig({
    required String baseUrl,
    this.connectTimeout = const Duration(seconds: 15),
    this.sendTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 30),
    Map<String, dynamic>? defaultHeaders,
    this.authHeaderName = 'Authorization',
    this.authHeaderBuilder = _bearer,
    List<PathMatcher>? publicPathMatchers,
    this.retry = const RetryConfig(),
    this.enableLogging,
    this.reachabilityUrl,
    this.extraDioInterceptors = const [],
    this.sha256Pins = const [],
  })  : baseUrl = _normalizeBaseUrl(baseUrl),
        defaultHeaders = Map<String, dynamic>.unmodifiable({
          'Accept': 'application/json',
          ...?defaultHeaders,
        }),
        publicPathMatchers = List<PathMatcher>.unmodifiable(
          publicPathMatchers ?? const [_defaultPublicPath],
        );

  final String baseUrl;
  final Duration connectTimeout;
  final Duration sendTimeout;
  final Duration receiveTimeout;
  final Map<String, dynamic> defaultHeaders;
  final String authHeaderName;
  final AuthHeaderBuilder authHeaderBuilder;
  final List<PathMatcher> publicPathMatchers;
  final RetryConfig retry;
  final bool? enableLogging;
  final String? reachabilityUrl;
  final List<Interceptor> extraDioInterceptors;

  /// Reserved for a future IO-only pinning adapter. Ignored on web.
  final List<String> sha256Pins;

  bool isPublicPath(String path) {
    for (final matcher in publicPathMatchers) {
      if (matcher(path)) {
        return true;
      }
    }
    return false;
  }

  static String _bearer(String token) => 'Bearer $token';

  static bool _defaultPublicPath(String path) {
    final normalized = path.toLowerCase();
    return normalized.contains('/login') ||
        normalized.contains('/refresh') ||
        normalized.contains('/health') ||
        normalized.contains('/register');
  }

  static String _normalizeBaseUrl(String url) {
    if (url.endsWith('/')) {
      return url;
    }
    return '$url/';
  }
}
