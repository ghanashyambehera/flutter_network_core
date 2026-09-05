# flutter_network_core — Design System

**Status:** Implemented (v0.1.0)  
**Based on:** [ANALYSIS.md](./ANALYSIS.md)  
**Date:** 5 September 2026  
**Target platforms:** Android, iOS, Web, macOS, Windows, Linux, Dart VM (tests / CLI)

This document is the implementation contract. The same `NetworkClient` API, interceptor pipeline, and exception types apply on every platform. Platform differences live only in **adapters**.

---

## 1. Design principles

| ID | Principle | Meaning |
|----|-----------|---------|
| P1 | **One API, many platforms** | Apps call `NetworkClient.get/post/...` the same way on mobile, web, and desktop. |
| P2 | **Package, not native plugin** | HTTP stays in Dart (Dio). No `android/` / `ios/` plugin folders. |
| P3 | **Core is platform-blind** | Client, interceptors, mapper, exceptions never import `dart:io`, `dart:html`, or Flutter widgets. |
| P4 | **Adapters at the edge** | Connectivity, token storage, file download, logging clock — injected interfaces. |
| P5 | **Configure, don’t fork** | `baseUrl`, timeouts, header scheme, refresh JSON, public paths are config + delegates. |
| P6 | **Fail with typed exceptions** | All Dio failures become `AppNetworkException` subtypes. No raw `DioException` leaks. |
| P7 | **No UI in the package** | No spinners, snackbars, or dialogs. Expose request lifecycle signals only. |
| P8 | **Secure by default** | Redact tokens in logs. Never log Authorization. Refresh uses a separate Dio. |

---

## 2. Packaging model (all platforms)

Publish **one Flutter package** named `flutter_network_core` (Dart SDK + Flutter SDK so default adapters can use `connectivity_plus` and `flutter_secure_storage`).

```
Pubspec
  flutter_network_core
    dio                          # all platforms
    connectivity_plus            # mobile, web, desktop
    flutter_secure_storage       # optional default TokenStorage
    meta
```

**Not a federated plugin.** Native reachability is already in `connectivity_plus`. Token vault is already in `flutter_secure_storage`.

**Conditional imports** (only inside adapters):

```dart
// src/adapters/connectivity/connectivity_factory.dart
import 'connectivity_stub.dart'
  if (dart.library.io) 'connectivity_io.dart'
  if (dart.library.js_interop) 'connectivity_web.dart';
```

Use `dart.library.js_interop` (not `dart.library.html`) so **web + Wasm** both resolve.

**Dart VM / unit tests:** inject `AlwaysOnlineConnectivity` + `MemoryTokenStorage`. No Flutter binding required for core tests.

---

## 3. Layered architecture

```
┌─────────────────────────────────────────────────────────────┐
│  App (any platform)                                         │
│  Repositories · fromJson · Bloc/Riverpod · logout routing   │
└────────────────────────────┬────────────────────────────────┘
                             │ NetworkClient
┌────────────────────────────▼────────────────────────────────┐
│  Public API                                                 │
│  NetworkClient · NetworkConfig · TokenPair                  │
│  TokenStorage · TokenRefreshDelegate · ConnectivityChecker  │
│  AppNetworkException family · RequestLifecycle              │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│  Core (pure Dart)                                           │
│  Dual Dio (auth + plain) · interceptors · ExceptionMapper   │
└────────────────────────────┬────────────────────────────────┘
                             │ interfaces
┌────────────────────────────▼────────────────────────────────┐
│  Platform adapters                                          │
│  Connectivity · TokenStorage · DownloadSink · Logger        │
└─────────────────────────────────────────────────────────────┘
```

Rules:

- Layers depend **downward only**.
- Core never constructs `SharedPreferences`, `dart:html` `window`, or `File` directly.
- Apps may replace any adapter.

---

## 4. Platform capability matrix

Same client. Different default adapters.

| Capability | Android | iOS | Web | macOS | Windows | Linux | Dart VM |
|------------|:-------:|:---:|:---:|:-----:|:-------:|:-----:|:-------:|
| Dio HTTP methods | yes | yes | yes + CORS | yes | yes | yes | yes |
| Timeouts / retry / CancelToken | yes | yes | yes | yes | yes | yes | yes |
| Typed exceptions | yes | yes | yes | yes | yes | yes | yes |
| Queued token refresh | yes | yes | yes | yes | yes | yes | yes |
| Link-status connectivity | `connectivity_plus` | same | browser online | same | same | same | inject stub |
| Secure token store | Keystore | Keychain | WebCrypto / browser | Keychain | DPAPI | libsecret | memory |
| Multipart upload | yes | yes | yes | yes | yes | yes | yes |
| File download to path | filesystem | filesystem | **blob / bytes** (no path) | filesystem | filesystem | filesystem | filesystem |
| TLS pinning | optional later | optional later | **not available** | optional | optional | optional | optional |
| Cookie / session APIs | header tokens default | same | CORS + optional cookies | same | same | same | same |

**Web-specific rules (must be in v1 design):**

1. Refresh and API hosts must allow CORS (or a same-origin proxy).
2. Do not assume `savePath` downloads; expose `downloadBytes` on all platforms; map to file only when `DownloadSink` supports paths.
3. `flutter_secure_storage` on web is not as strong as Keychain — document that; apps may use httpOnly cookies via a custom `TokenStorage` that is a no-op if the server sets cookies.
4. Certificate pinning is **unsupported on web**; `NetworkConfig.pinning` is ignored with a debug log.

**Desktop:** same as mobile for HTTP. Token storage backends differ; the `TokenStorage` interface hides that.

---

## 5. Module design (folders)

```
flutter_network_core/
  DESIGN.md
  ANALYSIS.md
  lib/
    flutter_network_core.dart
    src/
      config/network_config.dart
      client/network_client.dart
      client/dio_factory.dart
      interceptors/
        connectivity_interceptor.dart
        auth_interceptor.dart
        refresh_interceptor.dart
        retry_interceptor.dart
        logging_interceptor.dart
      auth/
        token_pair.dart
        token_storage.dart
        token_refresh_delegate.dart
      connectivity/connectivity_checker.dart
      download/download_sink.dart
      exceptions/
        app_network_exception.dart
        exception_mapper.dart
      lifecycle/request_lifecycle.dart
      adapters/
        connectivity/
        storage/
        download/
        logger/
  test/                    # core, HttpClientAdapter mocks — all platforms
  example/                 # Flutter app: Android, iOS, Web, desktop
```

Public barrel exports **only** types apps need. Interceptors stay `src/`.

---

## 6. Public API contract

### 6.1 NetworkConfig

| Field | Default | Notes |
|-------|---------|--------|
| `baseUrl` | required | Trailing-slash normalized |
| `connectTimeout` | 15s | All platforms |
| `sendTimeout` | 30s | All platforms |
| `receiveTimeout` | 30s | All platforms |
| `defaultHeaders` | `{Accept: application/json}` | Merged per request |
| `authHeaderName` | `Authorization` | Configurable |
| `authHeaderBuilder` | `(token) => 'Bearer $token'` | Custom schemes |
| `publicPathMatchers` | login/refresh/health | Skip auth + skip refresh |
| `retry` | 2 extra attempts, backoff, 408/429/5xx/timeout | Disabled per-request via `extra` |
| `enableLogging` | `kDebugMode` | Always redact auth headers |
| `validateStatus` | 2xx success | 4xx/5xx → mapper |
| `extraDioInterceptors` | empty | App-specific (tracing, etc.) |

### 6.2 NetworkClient

```dart
abstract class NetworkClient {
  /// Authenticated client (token + refresh).
  Future<T> get<T>(String path, {Map<String, dynamic>? query, ...});
  Future<T> post<T>(String path, {Object? data, ...});
  Future<T> put<T>(String path, {Object? data, ...});
  Future<T> patch<T>(String path, {Object? data, ...});
  Future<T> delete<T>(String path, {Object? data, ...});
  Future<T> head<T>(String path, {...});
  Future<T> upload<T>(String path, {required FormData data, ProgressCallback? onSendProgress});

  /// Bytes download — works on web and IO.
  Future<List<int>> downloadBytes(String pathOrUrl, {ProgressCallback? onReceiveProgress});

  /// Path download — throws UnsupportedError on web unless a web DownloadSink is provided.
  Future<void> downloadTo(String pathOrUrl, String savePath, {ProgressCallback? onReceiveProgress});

  /// No auth interceptor — login, register, refresh, public CMS.
  NetworkClient get unauthenticated;

  Stream<int> get pendingRequestCount;
  void close();
}
```

Per-request extras (via `Options.extra` or wrapper params):

- `skipAuth: true`
- `skipRetry: true`
- `skipConnectivityCheck: true`

### 6.3 Dual Dio (non-negotiable)

| Instance | Interceptor stack (order) | Use |
|----------|---------------------------|-----|
| **plain** | connectivity → retry → logging | Login, refresh, public |
| **auth** | connectivity → auth → refresh (queued) → retry → logging | Everything else |

`TokenRefreshDelegate.refresh` **must** use `plain` (or its own Dio). Package passes `plain` into the default delegate helper so apps cannot accidentally attach refresh to the auth client.

Refresh concurrency: `QueuedInterceptor`, one in-flight refresh, waiters retry with new access token. Multipart: rebuild `FormData` on retry.

---

## 7. Adapter interfaces (platform seam)

```dart
abstract class ConnectivityChecker {
  Future<bool> get isOnline;
  Stream<bool> get onChanged;
}

abstract class TokenStorage {
  Future<TokenPair?> read();
  Future<void> write(TokenPair pair);
  Future<void> clear();
}

abstract class TokenRefreshDelegate {
  Future<TokenPair> refresh(String refreshToken);
}

abstract class DownloadSink {
  Future<void> save(List<int> bytes, String suggestedNameOrPath);
}

abstract class NetworkLogger {
  void log(String message);
}
```

### Default adapters by platform

| Interface | Default (mobile/desktop) | Default (web) | Tests / VM |
|-----------|--------------------------|---------------|------------|
| ConnectivityChecker | `ConnectivityPlusChecker` | same (browser) | `AlwaysOnlineChecker` |
| TokenStorage | `SecureTokenStorage` | `SecureTokenStorage` (document limits) or `MemoryTokenStorage` | `MemoryTokenStorage` |
| DownloadSink | `FileDownloadSink` (`dart:io`) | `BrowserDownloadSink` (anchor + blob) | `MemoryDownloadSink` |
| NetworkLogger | `debugPrint` | `debugPrint` | no-op / print |

Apps that use **httpOnly cookies** implement `TokenStorage` as empty read/write and set `authHeaderBuilder` to omit Bearer; Dio `withCredentials` via `extraDioInterceptors` / adapter config.

---

## 8. Interceptor pipeline (auth client)

```
onRequest
  1. RequestLifecycle.increment
  2. ConnectivityInterceptor     → offline? throw NetworkException (no HTTP)
  3. AuthInterceptor             → if not public: attach access token
  4. LoggingInterceptor          → redact secrets

HTTP

onResponse / onError
  5. RefreshInterceptor          → 401 + protected → single-flight refresh → retry
  6. RetryInterceptor            → timeout / 429 / 5xx (not 401)
  7. ExceptionMapper             → DioException → AppNetworkException
  8. RequestLifecycle.decrement
```

Session expiry: refresh fails or 401 after successful refresh → `TokenStorage.clear()`, `SessionExpiredException`, `onSessionExpired` (once per expiry wave, debounced).

---

## 9. Exception design system

Sealed hierarchy. Same types on every platform.

```
AppNetworkException
  message · statusCode? · requestPath? · cause?
  ├── NetworkException          offline, DNS, socket, connection reset
  ├── TimeoutException          connect / send / receive timeout (lagging)
  ├── AuthenticationException   401 on public/login (bad credentials)
  ├── AuthorizationException    403
  ├── SessionExpiredException   refresh failed or unrecoverable 401
  ├── ClientException           other 4xx (400, 404, 409, 422…)
  ├── ServerException           5xx
  └── CancelledException        CancelToken
```

| Source | Type |
|--------|------|
| Connectivity false / `connectionError` | `NetworkException` |
| Timeout types | `TimeoutException` |
| 401 + `skipAuth` / public path | `AuthenticationException` |
| 401 + refresh success | no throw (retry) |
| 401 + refresh fail | `SessionExpiredException` |
| 403 | `AuthorizationException` |
| other 4xx | `ClientException` |
| 5xx | `ServerException` |
| cancel | `CancelledException` |

Mapper reads **server message** from common keys (`message`, `error`, `detail`, `title`) without assuming a single JSON schema.

Apps map exceptions → UI copy / localization. Package stays language-neutral.

---

## 10. Connectivity and lagging (all platforms)

**Connectivity**

- Fail fast before HTTP when `isOnline == false`.
- Stream for banners.
- Document: link-up ≠ working internet. Optional `NetworkConfig.reachabilityUrl` (HEAD) — off by default; on web this URL must be CORS-allowed.

**Lagging**

| Control | Role |
|---------|------|
| Three Dio timeouts | Bound wait |
| Retry + exponential backoff + jitter | Transient failures |
| `CancelToken` | Leave screen / widget dispose |
| `pendingRequestCount` | App loading overlay |

No overlay widget in the package (P7). Example app shows one pattern per platform (Material / Cupertino still in **example**, not in core).

---

## 11. Security design

| Topic | Rule |
|-------|------|
| Access token | Memory + `TokenStorage`; inject via interceptor only |
| Refresh token | Never attach to normal APIs; only refresh call |
| Logs | Strip `Authorization`, `Cookie`, token JSON fields |
| Refresh Dio | No auth interceptor |
| Web | Prefer CORS + Bearer; cookies only if app opts in (`withCredentials`) |
| Pinning | IO-only optional (v2); no-op on web |
| Clear on session expire | Always |

---

## 12. Request lifecycle (loading, not UI)

```dart
abstract class RequestLifecycle {
  Stream<int> get pendingCount;
  Stream<NetworkEvent> get events; // start, end, error (typed)
}
```

App binds:

- Mobile/desktop: overlay / `EasyLoading` / Bloc
- Web: top progress bar
- Same stream. Different UI.

---

## 13. Example app (proves all platforms)

`example/` is a Flutter project with:

- Login (plain client) → persist `TokenPair`
- Authenticated `GET`
- Forced 401 → refresh → retry
- Toggle airplane / browser offline → `NetworkException`
- Slow endpoint → `TimeoutException`
- Logout on `SessionExpiredException`

Build matrix: Android, iOS, Chrome, macOS. Windows/Linux same as macOS for this package.

---

## 14. Testing design

| Layer | How | Platforms |
|-------|-----|-----------|
| ExceptionMapper | unit, fake `DioException` | VM |
| Refresh queue | `Dio` + `HttpClientAdapter` mock, 3 parallel 401s → 1 refresh | VM |
| Connectivity interceptor | fake checker | VM |
| Retry backoff | fake adapter | VM |
| Example | integration, optional | device / Chrome |

Core tests must pass with `flutter test` on CI without Android emulator.

---

## 15. Versioning and compatibility

| Item | Choice |
|------|--------|
| Dart | SDK aligned with current Flutter stable |
| Dio | 5.x |
| Breaking changes | `NetworkConfig` / exception types: semver major |
| Flutter web Wasm | adapters via `js_interop` |

---

## 16. Implementation phases (aligned with analysis)

| Phase | Design slice |
|-------|----------------|
| 1 | Config, client methods, exceptions, mapper, dual Dio |
| 2 | Interceptors (connectivity, auth, queued refresh, retry, log) |
| 3 | Default adapters: plus / secure storage / IO + web download |
| 4 | Example on mobile + web |
| 5 | Mapper + refresh-queue tests |
| 6 | Publish |

---

## 17. Decision summary

1. **Not a plugin** — Dart package with injectable adapters.  
2. **All Flutter platforms + tests on VM** — identical exceptions and HTTP API.  
3. **Web is first-class** — bytes download, CORS, no pinning, Wasm-safe imports.  
4. **Apps only write** repositories, refresh JSON, and UI for errors/loading.  
5. **This file is the spec** for scaffolding `lib/` when implementation starts.

Related: [ANALYSIS.md](./ANALYSIS.md) (feasibility). This file (architecture and platform contract).
