# flutter_network_core

![pub package](https://img.shields.io/pub/v/flutter_network_core.svg)
![likes](https://img.shields.io/pub/likes/flutter_network_core)
![pub points](https://img.shields.io/pub/points/flutter_network_core)
![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)

A reusable **Dio** network layer for Flutter. Configure `baseUrl` and token refresh once; feature code only calls `get` / `post` / `put` / `patch` / `delete`.

The package owns interceptors, connectivity checks, timeouts, queued access/refresh tokens, and typed exceptions so you do not copy the same `api_client.dart` into every project.

This is a **Dart package**, not a native plugin. HTTP stays in Dio. Platform differences (Keychain, browser, files) are adapters.

| Android | iOS | Web | macOS | Windows | Linux |
| ------- | --- | --- | ----- | ------- | ----- |
| ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## Features

- **All HTTP methods** — `get`, `post`, `put`, `patch`, `delete`, `head`, multipart `upload`, `downloadBytes`.
- **Two Dio clients** — authenticated APIs vs login/refresh/public (`unauthenticated`). Refresh never loops on itself.
- **Queued token refresh** — concurrent 401s share **one** refresh, then retry with the new access token.
- **Typed exceptions** — `NetworkException`, `AuthenticationException`, `AuthorizationException`, `SessionExpiredException`, `ServerException`, and more. No raw `DioException` in app code.
- **Connectivity** — fail fast when offline (`connectivity_plus`). Optional live `onChanged` stream.
- **Lagging / flaky networks** — connect/send/receive timeouts, retry with backoff, `CancelToken`.
- **Secure tokens** — `SecureTokenStorage` (Keystore / Keychain / DPAPI / WebCrypto) or `MemoryTokenStorage` for tests.
- **No UI** — expose `pendingRequestCount` so each app binds its own overlay or progress bar.
- **Testable** — inject `HttpClientAdapter`, `AlwaysOnlineChecker`, and in-memory storage.

---

## Install

```yaml
dependencies:
  flutter_network_core: ^0.1.0
```

```sh
flutter pub get
```

From a path or Git submodule (before / besides pub.dev):

```yaml
dependencies:
  flutter_network_core:
    git:
      url: https://github.com/ghanashyambehera/flutter_network_core.git
```

---

## Quick start

```dart
import 'package:flutter_network_core/flutter_network_core.dart';

final network = NetworkClient(
  config: NetworkConfig(
    baseUrl: 'https://api.example.com',
    connectTimeout: Duration(seconds: 15),
    sendTimeout: Duration(seconds: 30),
    receiveTimeout: Duration(seconds: 30),
  ),
  tokenStorage: SecureTokenStorage(),
  connectivity: ConnectivityPlusChecker(),
  refreshDelegateBuilder: (plain) => HttpTokenRefreshDelegate(
    client: plain, // always the unauthenticated Dio
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
    // Clear session and navigate to login.
  },
);
```

Feature repository (project-specific):

```dart
class UserRepository {
  UserRepository(this._network);
  final NetworkClient _network;

  Future<Map<String, dynamic>> me() {
    return _network.get<Map<String, dynamic>>('/users/me');
  }
}
```

---

## HTTP API

```dart
await network.get<Map<String, dynamic>>('/users/me');
await network.post<Map<String, dynamic>>('/items', data: {'name': 'Tea'});
await network.put<Map<String, dynamic>>('/items/1', data: {'name': 'Coffee'});
await network.patch<Map<String, dynamic>>('/items/1', data: {'done': true});
await network.delete<void>('/items/1');
await network.head<void>('/health');

await network.upload<Map<String, dynamic>>(
  '/files',
  data: FormData.fromMap({
    'file': await MultipartFile.fromFile(path),
  }),
);

final bytes = await network.downloadBytes('/files/1');
await network.downloadTo('/files/1', '/tmp/file.bin'); // IO platforms only
```

Per-request flags:

```dart
await network.get<Map<String, dynamic>>(
  '/public/cms',
  skipAuth: true,
  skipRetry: true,
  skipConnectivityCheck: true,
);
```

---

## Login vs authenticated calls

| Client | Use for |
|--------|---------|
| `network.unauthenticated` | Login, register, forgot password, public CMS |
| `network` (default) | Everything that needs a Bearer access token |

```dart
final tokens = await network.unauthenticated.post<Map<String, dynamic>>(
  '/auth/login',
  data: {'email': email, 'password': password},
);

await network.tokenStorage.write(
  TokenPair(
    accessToken: tokens['accessToken'] as String,
    refreshToken: tokens['refreshToken'] as String,
  ),
);
```

Default public paths (no auth header, no refresh): URL contains `/login`, `/refresh`, `/health`, or `/register`. Override with `NetworkConfig.publicPathMatchers`.

---

## Token refresh

1. Protected call returns **401**.
2. `QueuedInterceptor` runs **one** refresh via `TokenRefreshDelegate` on the **plain** Dio.
3. New `TokenPair` is saved.
4. Original request(s) retry with the new access token.
5. If refresh fails → tokens cleared, `SessionExpiredException`, `onSessionExpired`.

Implement `TokenRefreshDelegate` yourself if the refresh contract is not a simple POST + JSON map.

---

## Exceptions

Catch `AppNetworkException` in a global handler, or match subtypes.

| Type | When |
|------|------|
| `NetworkException` | Offline, DNS, socket, connection error |
| `NetworkTimeoutException` | Connect / send / receive timeout |
| `AuthenticationException` | **401** on login or another public path (bad credentials) |
| `AuthorizationException` | **403** |
| `SessionExpiredException` | Refresh failed or unrecoverable 401 on a protected call |
| `ClientException` | Other **4xx** (400, 404, 409, 422, …) |
| `ServerException` | **5xx** |
| `CancelledException` | `CancelToken` |

401 is split on purpose: wrong password is not the same as an expired session.

```dart
try {
  await network.get<Map<String, dynamic>>('/users/me');
} on SessionExpiredException {
  // Force logout.
} on NetworkException {
  // Show offline banner.
} on AppNetworkException catch (e) {
  debugPrint(e.message);
}
```

---

## Connectivity and loading

Offline requests throw `NetworkException` before HTTP.

```dart
network.connectivity.onChanged.listen((online) {
  // Banner / snackbar.
});

network.pendingRequestCount.listen((count) {
  // Overlay / top progress bar. This package has no widgets.
});
```

Timeouts and retries (lagging networks):

| Setting | Default |
|---------|---------|
| `connectTimeout` | 15s |
| `sendTimeout` / `receiveTimeout` | 30s |
| Extra retry attempts | 2 |
| Retry status codes | 408, 429, 500, 502, 503, 504 |

```dart
NetworkConfig(
  baseUrl: 'https://api.example.com',
  retry: RetryConfig(
    maxExtraAttempts: 2,
    initialBackoff: Duration(milliseconds: 300),
    retryableStatusCodes: {408, 429, 500, 502, 503, 504},
  ),
);
```

---

## Configuration

| Field | Meaning |
|-------|---------|
| `baseUrl` | Required. Trailing slash is normalized. |
| `defaultHeaders` | Merged with `Accept: application/json`. |
| `authHeaderName` | Default `Authorization`. |
| `authHeaderBuilder` | Default `(token) => 'Bearer $token'`. |
| `publicPathMatchers` | Skip auth + refresh. |
| `enableLogging` | Default: on in debug. Authorization and tokens are redacted. |
| `reachabilityUrl` | Optional HEAD probe (link-up ≠ internet). Off by default. CORS required on web. |
| `extraDioInterceptors` | Tracing, cookies (`withCredentials`), etc. |
| `sha256Pins` | Reserved; **ignored on web**. |

---

## Platform notes

| Capability | Mobile / desktop | Web |
|------------|------------------|-----|
| HTTP + interceptors + exceptions | Yes | Yes (API must allow **CORS**) |
| `SecureTokenStorage` | Keystore / Keychain / DPAPI | WebCrypto (weaker than Keychain) |
| `downloadBytes` | Yes | Yes |
| `downloadTo(path)` | File system | Unsupported — use `downloadBytes` |
| TLS pinning | Planned (IO) | Not available |

For httpOnly cookies, implement a no-op `TokenStorage` and attach credentials with `extraDioInterceptors`.

Android / iOS: `connectivity_plus` and `flutter_secure_storage` may need the usual permission / Keychain setup from those packages.

---

## Testing

```dart
final client = NetworkClient(
  config: NetworkConfig(
    baseUrl: 'https://api.test',
    enableLogging: false,
    retry: RetryConfig(maxExtraAttempts: 0),
  ),
  tokenStorage: MemoryTokenStorage(),
  connectivity: AlwaysOnlineChecker(),
  httpClientAdapter: myFakeAdapter,
  usePluginConnectivity: false,
);
```

Run package tests:

```sh
cd flutter_network_core
flutter test
```

---

## Example

The `example/` app uses an in-memory mock adapter (no live backend): login, authenticated GET, forced 401 refresh, offline, session expiry.

```sh
cd example
flutter run
```

---

## Publishing on pub.dev

Checklist used for this package:

1. `pubspec.yaml` — `name`, `description`, `version`, `homepage`, `repository`, `issue_tracker`, `topics`.
2. `README.md` (this file), `CHANGELOG.md`, `LICENSE`.
3. `example/` so pub.dev can show usage.
4. `dart analyze` and `flutter test` are clean.
5. Publish:

```sh
dart pub publish --dry-run
dart pub publish
```

You need a [pub.dev](https://pub.dev) account linked to the GitHub publisher (verified publisher recommended).

---

## Design docs

- [ANALYSIS.md](ANALYSIS.md) — why a package (not a plugin).
- [DESIGN.md](DESIGN.md) — architecture, adapters, exception mapping.

Repository: [github.com/ghanashyambehera/flutter_network_core](https://github.com/ghanashyambehera/flutter_network_core)

---

## License

BSD 3-Clause. See [LICENSE](LICENSE).
