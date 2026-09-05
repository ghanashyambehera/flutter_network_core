import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../adapters/connectivity/always_online_checker.dart';
import '../adapters/connectivity/connectivity_plus_checker.dart';
import '../adapters/download/download_sink_factory.dart';
import '../adapters/logger/debug_print_logger.dart';
import '../adapters/logger/network_logger.dart';
import '../adapters/storage/memory_token_storage.dart';
import '../auth/token_refresh_delegate.dart';
import '../auth/token_storage.dart';
import '../config/network_config.dart';
import '../config/request_flags.dart';
import '../connectivity/connectivity_checker.dart';
import '../download/download_sink.dart';
import '../exceptions/app_network_exception.dart';
import '../exceptions/exception_mapper.dart';
import '../lifecycle/request_lifecycle.dart';
import 'dio_factory.dart';

class NetworkClient {
  factory NetworkClient({
    required NetworkConfig config,
    TokenStorage? tokenStorage,
    TokenRefreshDelegate? refreshDelegate,
    TokenRefreshDelegate Function(Dio unauthenticatedClient)?
        refreshDelegateBuilder,
    ConnectivityChecker? connectivity,
    DownloadSink? downloadSink,
    NetworkLogger? logger,
    void Function()? onSessionExpired,
    HttpClientAdapter? httpClientAdapter,
    DioFactory dioFactory = const DioFactory(),
    ExceptionMapper mapper = const ExceptionMapper(),
    bool usePluginConnectivity = true,
  }) {
    final storage = tokenStorage ?? MemoryTokenStorage();
    final checker = connectivity ??
        (usePluginConnectivity
            ? ConnectivityPlusChecker()
            : const AlwaysOnlineChecker());
    final sink = downloadSink ?? createDefaultDownloadSink();
    final resolvedLogger = logger ?? const DebugPrintLogger();
    final lifecycle = RequestLifecycle();

    final plain = dioFactory.create(
      config: config,
      connectivity: checker,
      storage: storage,
      authenticated: false,
      logger: resolvedLogger,
      httpClientAdapter: httpClientAdapter,
    );
    final delegate = refreshDelegateBuilder?.call(plain) ?? refreshDelegate;
    final auth = dioFactory.create(
      config: config,
      connectivity: checker,
      storage: storage,
      authenticated: true,
      refreshDelegate: delegate,
      onSessionExpired: onSessionExpired,
      logger: resolvedLogger,
      httpClientAdapter: httpClientAdapter,
    );

    final client = NetworkClient._(
      config: config,
      storage: storage,
      connectivity: checker,
      downloadSink: sink,
      logger: resolvedLogger,
      mapper: mapper,
      lifecycle: lifecycle,
      dio: auth,
      auth: auth,
      plain: plain,
    );
    client._unauthenticated = NetworkClient._(
      config: config,
      storage: storage,
      connectivity: checker,
      downloadSink: sink,
      logger: resolvedLogger,
      mapper: mapper,
      lifecycle: lifecycle,
      dio: plain,
      auth: auth,
      plain: plain,
      unauthenticated: client,
    );
    return client;
  }

  NetworkClient._({
    required NetworkConfig config,
    required TokenStorage storage,
    required ConnectivityChecker connectivity,
    required DownloadSink downloadSink,
    required NetworkLogger logger,
    required ExceptionMapper mapper,
    required RequestLifecycle lifecycle,
    required Dio dio,
    required Dio auth,
    required Dio plain,
    NetworkClient? unauthenticated,
  })  : _config = config,
        _storage = storage,
        _connectivity = connectivity,
        _downloadSink = downloadSink,
        _logger = logger,
        _mapper = mapper,
        _lifecycle = lifecycle,
        _dio = dio,
        _auth = auth,
        _plain = plain,
        _unauthenticated = unauthenticated;

  final NetworkConfig _config;
  final TokenStorage _storage;
  final ConnectivityChecker _connectivity;
  final DownloadSink _downloadSink;
  final NetworkLogger _logger;
  final ExceptionMapper _mapper;
  final RequestLifecycle _lifecycle;
  final Dio _dio;
  final Dio _auth;
  final Dio _plain;
  NetworkClient? _unauthenticated;

  TokenStorage get tokenStorage => _storage;
  ConnectivityChecker get connectivity => _connectivity;
  NetworkLogger get logger => _logger;
  RequestLifecycle get lifecycle => _lifecycle;

  /// Login, register, refresh, and other public calls (no auth interceptor).
  NetworkClient get unauthenticated => _unauthenticated ?? this;

  Stream<int> get pendingRequestCount => _lifecycle.pendingCount;

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    bool skipAuth = false,
    bool skipRetry = false,
    bool skipConnectivityCheck = false,
    ProgressCallback? onReceiveProgress,
  }) {
    return request<T>(
      path,
      method: 'GET',
      query: query,
      headers: headers,
      cancelToken: cancelToken,
      skipAuth: skipAuth,
      skipRetry: skipRetry,
      skipConnectivityCheck: skipConnectivityCheck,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    bool skipAuth = false,
    bool skipRetry = false,
    bool skipConnectivityCheck = false,
    ProgressCallback? onSendProgress,
  }) {
    return request<T>(
      path,
      method: 'POST',
      data: data,
      query: query,
      headers: headers,
      cancelToken: cancelToken,
      skipAuth: skipAuth,
      skipRetry: skipRetry,
      skipConnectivityCheck: skipConnectivityCheck,
      onSendProgress: onSendProgress,
    );
  }

  Future<T> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    bool skipAuth = false,
    bool skipRetry = false,
    bool skipConnectivityCheck = false,
  }) {
    return request<T>(
      path,
      method: 'PUT',
      data: data,
      query: query,
      headers: headers,
      cancelToken: cancelToken,
      skipAuth: skipAuth,
      skipRetry: skipRetry,
      skipConnectivityCheck: skipConnectivityCheck,
    );
  }

  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    bool skipAuth = false,
    bool skipRetry = false,
    bool skipConnectivityCheck = false,
  }) {
    return request<T>(
      path,
      method: 'PATCH',
      data: data,
      query: query,
      headers: headers,
      cancelToken: cancelToken,
      skipAuth: skipAuth,
      skipRetry: skipRetry,
      skipConnectivityCheck: skipConnectivityCheck,
    );
  }

  Future<T> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    bool skipAuth = false,
    bool skipRetry = false,
    bool skipConnectivityCheck = false,
  }) {
    return request<T>(
      path,
      method: 'DELETE',
      data: data,
      query: query,
      headers: headers,
      cancelToken: cancelToken,
      skipAuth: skipAuth,
      skipRetry: skipRetry,
      skipConnectivityCheck: skipConnectivityCheck,
    );
  }

  Future<T> head<T>(
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    bool skipAuth = false,
    bool skipRetry = false,
    bool skipConnectivityCheck = false,
  }) {
    return request<T>(
      path,
      method: 'HEAD',
      query: query,
      headers: headers,
      cancelToken: cancelToken,
      skipAuth: skipAuth,
      skipRetry: skipRetry,
      skipConnectivityCheck: skipConnectivityCheck,
    );
  }

  Future<T> upload<T>(
    String path, {
    required FormData data,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    bool skipAuth = false,
    bool skipRetry = false,
    bool skipConnectivityCheck = false,
  }) {
    return request<T>(
      path,
      method: 'POST',
      data: data,
      query: query,
      headers: headers,
      cancelToken: cancelToken,
      skipAuth: skipAuth,
      skipRetry: skipRetry,
      skipConnectivityCheck: skipConnectivityCheck,
      onSendProgress: onSendProgress,
    );
  }

  Future<List<int>> downloadBytes(
    String pathOrUrl, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
    bool skipAuth = false,
    bool skipRetry = false,
    bool skipConnectivityCheck = false,
  }) async {
    final data = await request<dynamic>(
      pathOrUrl,
      method: 'GET',
      query: query,
      headers: headers,
      cancelToken: cancelToken,
      skipAuth: skipAuth,
      skipRetry: skipRetry,
      skipConnectivityCheck: skipConnectivityCheck,
      onReceiveProgress: onReceiveProgress,
      responseType: ResponseType.bytes,
    );
    if (data is Uint8List) {
      return data;
    }
    if (data is List<int>) {
      return data;
    }
    throw const ClientException(message: 'Download did not return bytes.');
  }

  Future<void> downloadTo(
    String pathOrUrl,
    String savePath, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
    bool skipAuth = false,
    bool skipRetry = false,
    bool skipConnectivityCheck = false,
  }) async {
    if (!_downloadSink.supportsPath) {
      throw UnsupportedError(
        'Path downloads are not available on this platform. Use downloadBytes().',
      );
    }
    final bytes = await downloadBytes(
      pathOrUrl,
      query: query,
      headers: headers,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      skipAuth: skipAuth,
      skipRetry: skipRetry,
      skipConnectivityCheck: skipConnectivityCheck,
    );
    await _downloadSink.save(bytes, savePath);
  }

  Future<T> request<T>(
    String path, {
    required String method,
    Object? data,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    bool skipAuth = false,
    bool skipRetry = false,
    bool skipConnectivityCheck = false,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    ResponseType? responseType,
  }) async {
    _lifecycle.start(path);
    try {
      final response = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
        options: Options(
          method: method,
          headers: headers,
          responseType: responseType,
          extra: {
            RequestFlags.skipAuth: skipAuth,
            RequestFlags.skipRetry: skipRetry,
            RequestFlags.skipConnectivity: skipConnectivityCheck,
          },
        ),
      );
      return response.data as T;
    } on DioException catch (error) {
      final mapped = _mapper.map(
        error,
        isPublic: skipAuth ||
            _config.isPublicPath(path) ||
            _config.isPublicPath(error.requestOptions.uri.path),
      );
      _lifecycle.error(path, mapped);
      throw mapped;
    } on AppNetworkException catch (error) {
      _lifecycle.error(path, error);
      rethrow;
    } finally {
      _lifecycle.end(path);
    }
  }

  void close({bool force = false}) {
    _auth.close(force: force);
    _plain.close(force: force);
    _lifecycle.close();
  }
}
