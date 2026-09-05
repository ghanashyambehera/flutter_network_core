/// Keys stored on [RequestOptions.extra].
abstract final class RequestFlags {
  static const skipAuth = 'fnc_skipAuth';
  static const skipRetry = 'fnc_skipRetry';
  static const skipConnectivity = 'fnc_skipConnectivity';
  static const refreshRetry = 'fnc_refreshRetry';
}
