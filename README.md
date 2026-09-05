# flutter_network_core

Reusable Dio network layer for Flutter apps on **Android, iOS, Web, macOS, Windows, and Linux**.

You configure `baseUrl` and refresh-token JSON once. Feature code only calls `get` / `post` / `put` / `patch` / `delete`. The package owns interceptors, connectivity, timeouts, queued token refresh, and typed exceptions.

This is a **Dart package**, not a native plugin. See [ANALYSIS.md](ANALYSIS.md) and [DESIGN.md](DESIGN.md).

## Install

```yaml
dependencies:
  flutter_network_core:
    path: ../flutter_network_core
```

## Setup

```dart
final network = NetworkClient(
  config: NetworkConfig(
    baseUrl: 'https://api.example.com',
    connectTimeout: Duration(seconds: 15),
    receiveTimeout: Duration(seconds: 30),
  ),
  tokenStorage: SecureTokenStorage(), // or MemoryTokenStorage()
  connectivity: ConnectivityPlusChecker(),
  refreshDelegateBuilder: (plain) => HttpTokenRefreshDelegate(
    client: plain, // never the authenticated client
    path: '/auth/refresh',
    bodyBuilder: (refreshToken) => {'refreshToken': refreshToken},
    parser: (data) {
      final map = data as Map<String, dynamic>;
      return TokenPair(
        accessToken: map['accessToken'] as String,
        refreshToken: map['refreshToken'] as String,
      );
    },
  ),
  onSessionExpired: () {
    // Navigate to login.
  },
);
```

## Calls

```dart
final profile = await network.get<Map<String, dynamic>>('/users/me');

await network.unauthenticated.post<Map<String, dynamic>>(
  '/auth/login',
  data: {'email': email, 'password': password},
);

await network.upload<Map<String, dynamic>>(
  '/files',
  data: FormData.fromMap({'file': await MultipartFile.fromFile(path)}),
);

final bytes = await network.downloadBytes('/files/1');
```

## Exceptions

Catch `AppNetworkException` globally, or match subtypes:

| Type | Typical cause |
|------|----------------|
| `NetworkException` | Offline / DNS / socket |
| `NetworkTimeoutException` | Connect / send / receive timeout |
| `AuthenticationException` | 401 on login or other public path |
| `AuthorizationException` | 403 |
| `SessionExpiredException` | Refresh failed |
| `ClientException` | Other 4xx |
| `ServerException` | 5xx |
| `CancelledException` | `CancelToken` |

## Loading

```dart
network.pendingRequestCount.listen((count) {
  // Bind your overlay / progress bar. The package has no UI.
});
```

## Tests

Inject `AlwaysOnlineChecker`, `MemoryTokenStorage`, and a fake `HttpClientAdapter`. Set `usePluginConnectivity: false`.
