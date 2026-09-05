# flutter_network_core — Feasibility Analysis

**Date:** 5 September 2026  
**Author:** Analysis for Ghanashyam  
**Goal:** Decide whether a reusable Flutter library can replace copy-paste Dio setup in every new project.

---

## 1. Verdict

**Yes. It is possible — and it is a good idea.**

The classes you rewrite on every project (Dio client, interceptors, token refresh, connectivity check, typed exceptions) are **shared infrastructure**, not app business logic. They belong in a reusable library.

**Correct packaging type:** a **Dart/Flutter package**, not a native plugin.

| Type | When to use | Fits this work? |
|------|-------------|-----------------|
| **Flutter plugin** | Needs Android/iOS/macOS native code (camera, Bluetooth, platform channels) | No — HTTP is already in Dart via Dio |
| **Flutter / Dart package** | Pure Dart + optional Flutter widgets, depends on other plugins if needed | **Yes** |

Connectivity and secure token storage already have native plugins (`connectivity_plus`, `flutter_secure_storage`). `flutter_network_core` should **depend on those**, not reimplement them.

You can still publish it like `flutter_mobile_diagnostics` (GitHub + pub.dev). Consumers add one dependency and configure once.

---

## 2. Why every project repeats this

Typical new Flutter app copies the same files:

```
lib/core/network/
  api_client.dart
  dio_client.dart
  interceptors/auth_interceptor.dart
  interceptors/refresh_interceptor.dart
  interceptors/logging_interceptor.dart
  exceptions/network_exceptions.dart
  connectivity_service.dart
```

Those files are **80–90% identical** across apps. What changes per project:

| Stays the same (belongs in the package) | Changes per app (must be configurable) |
|-----------------------------------------|----------------------------------------|
| GET / POST / PUT / PATCH / DELETE / upload | `baseUrl`, timeouts, extra headers |
| Dio interceptors pipeline | Refresh endpoint path and request/response JSON shape |
| Map Dio errors → typed exceptions | Where tokens are stored (secure storage vs your own) |
| Queue concurrent 401s and refresh once | Header name (`Authorization: Bearer …` vs custom) |
| Offline / no-network check | Which HTTP codes mean “session expired” vs “login failed” |
| Retry + timeout (“lagging”) policy | Loading UI (dialog, overlay, BLoC, Riverpod) |
| Global exception types | Domain models (`User`, `Order`) and endpoints |

The package should **not** know your REST paths or JSON models. It should expose a client + interceptors + exceptions. Each app writes thin repository methods on top.

---

## 3. Scope of `flutter_network_core`

### 3.1 In scope (core product)

1. **Single configured Dio client**  
   Timeouts, base URL, default headers, optional logging.

2. **All HTTP methods**  
   `get`, `post`, `put`, `patch`, `delete`, `head`, multipart upload, download.

3. **Connectivity**  
   Fail fast with `NetworkException` when there is no connection. Optional stream so the app can show “offline”.

4. **Lagging / slow network**  
   Connect / send / receive timeouts, optional retry with backoff for 408 / 429 / 5xx / timeouts, request cancellation via `CancelToken`.

5. **Auth interceptor**  
   Attach access token to outgoing requests. Skip public endpoints (login, refresh, health).

6. **Refresh interceptor (`QueuedInterceptor`)**  
   On 401: refresh **once**, queue other requests, retry originals with the new token. On refresh failure: `SessionExpiredException` and a callback (`onSessionExpired`) so the app can logout / navigate to login.

7. **Global exception mapping** (see section 5).

8. **Pluggable token store and refresh delegate**  
   Package defines interfaces. App implements storage and “how to call refresh”.

### 3.2 Out of scope (keep in the app)

- Feature APIs (`/users`, `/orders`, …)
- JSON → model parsing (or keep it optional via a generic `fromJson`)
- UI loaders, snackbars, localization of error messages
- GraphQL / WebSocket (can be a later package)
- Certificate pinning as a hard default (optional extra, not v1 required)

---

## 4. Recommended architecture

```
flutter_network_core/
  lib/
    flutter_network_core.dart          # public barrel
    src/
      config/
        network_config.dart            # baseUrl, timeouts, retry, headers
      client/
        network_client.dart            # get/post/put/patch/delete/upload
      interceptors/
        auth_interceptor.dart          # inject access token
        refresh_interceptor.dart       # QueuedInterceptor + single-flight refresh
        connectivity_interceptor.dart  # offline → NetworkException
        retry_interceptor.dart         # lagging / flaky network
        logging_interceptor.dart       # debug only
      auth/
        token_pair.dart
        token_storage.dart             # abstract
        token_refresh_delegate.dart    # abstract
      connectivity/
        connectivity_checker.dart      # abstract + default via connectivity_plus
      exceptions/
        app_exceptions.dart            # hierarchy below
        exception_mapper.dart          # DioException → typed exception
      result/                          # optional
        api_result.dart                # ApiResult<T> or Either-style
```

**Two Dio instances (required for refresh):**

| Instance | Interceptors | Used for |
|----------|--------------|----------|
| **Auth client** | connectivity + auth + refresh + retry + log | All authenticated APIs |
| **Plain client** | connectivity + retry + log, **no** auth/refresh | Login, refresh token, public APIs |

Refresh **must not** go through the auth interceptor. Otherwise a failed refresh 401 loops forever.

**Refresh concurrency:** use Dio `QueuedInterceptor`. If 5 APIs get 401 at once, only **one** refresh runs; the other four wait and retry with the new access token.

---

## 5. Exception model (global)

Package owns these types. Apps catch them in a global handler (BlocObserver, `runZonedGuarded`, or a single `onError` in the client).

```
AppNetworkException (base)
├── NetworkException          # offline, DNS, socket, connection timeout
├── AuthenticationException   # 401 when credentials are wrong (login/OTP), not expired session
├── AuthorizationException    # 403 forbidden
├── SessionExpiredException   # refresh failed or 401 after refresh; force logout
├── ServerException           # 5xx, unexpected server body
├── TimeoutException          # send/receive timeout (lagging)
├── CancelledException        # CancelToken
└── ClientException           # 4xx other than 401/403 (400, 404, 409, 422)
```

Suggested HTTP mapping (configurable):

| Status / Dio type | Exception |
|-------------------|-----------|
| No connection / `connectionError` | `NetworkException` |
| Connect / send / receive timeout | `TimeoutException` (or `NetworkException` if you prefer one type) |
| 401 on login/public call | `AuthenticationException` |
| 401 on protected call → refresh OK → retry | (no throw; request succeeds) |
| 401 after refresh fails / refresh 401 | `SessionExpiredException` |
| 403 | `AuthorizationException` |
| 4xx | `ClientException` |
| 5xx | `ServerException` |
| Request cancelled | `CancelledException` |

**401 is ambiguous.** Login returning 401 is “wrong password”. A later API returning 401 is usually “access token expired”. The interceptor should:

- Skip refresh for paths marked `isPublic` / `skipAuth`.
- Attempt refresh only for authenticated requests.
- If refresh fails → `SessionExpiredException`, not `AuthenticationException`.

---

## 6. Token & interceptor flow

```
Request
  → ConnectivityInterceptor   (offline? throw NetworkException)
  → AuthInterceptor           (add Bearer accessToken if present)
  → Dio HTTP
Response 401 (protected)
  → RefreshInterceptor
       lock queue
       call TokenRefreshDelegate with refreshToken (plain Dio)
       save new TokenPair via TokenStorage
       retry original request
       unlock queue
  if refresh fails
       clear tokens
       throw SessionExpiredException
       invoke onSessionExpired
```

**App must provide:**

```dart
abstract class TokenStorage {
  Future<TokenPair?> read();
  Future<void> write(TokenPair pair);
  Future<void> clear();
}

abstract class TokenRefreshDelegate {
  /// Called with the current refresh token. Return a new pair.
  Future<TokenPair> refresh(String refreshToken);
}
```

Default storage can be optional (`FlutterSecureStorage` adapter). Refresh **body shape** cannot be hardcoded (`refresh_token` vs `refreshToken` vs cookie). The delegate is the extension point.

---

## 7. Connectivity and lagging

**Connectivity**

- Check before send (interceptor).
- Optional `Stream<bool> onConnectivityChanged`.
- Caveat: “Wi‑Fi connected” ≠ “internet works”. Optional lightweight HEAD/GET to a health URL can be a config flag, not default.

**Lagging**

| Mechanism | Purpose |
|-----------|---------|
| `connectTimeout` / `receiveTimeout` / `sendTimeout` | Bound wait time |
| Retry interceptor (max 2–3, backoff) | Transient 429 / 502 / 503 / timeout |
| `CancelToken` | User left the screen |
| Optional request timeout wrapper | Extra safety beyond Dio |

The package should **not** show a loading spinner. Expose:

- `onRequestStart` / `onRequestEnd` callbacks, or
- a `pendingRequestCount` stream  

The app binds that to Overlay / Bloc / Riverpod.

---

## 8. What the consuming app still writes (intentionally small)

```dart
// once in main / DI
final network = NetworkClient(
  config: NetworkConfig(
    baseUrl: 'https://api.myapp.com',
    connectTimeout: Duration(seconds: 15),
    receiveTimeout: Duration(seconds: 30),
  ),
  tokenStorage: SecureTokenStorage(),
  refreshDelegate: MyRefreshDelegate(), // POST /auth/refresh, parse JSON
  onSessionExpired: () => authCubit.logout(),
);

// per feature — only this is project-specific
class UserRepository {
  UserRepository(this._network);
  final NetworkClient _network;

  Future<User> me() async {
    final json = await _network.get<Map<String, dynamic>>('/users/me');
    return User.fromJson(json);
  }
}
```

No Dio setup, no interceptor copy-paste, no exception classes per project.

---

## 9. Plugin vs package — extra note for this repo

This workspace already has `flutter_mobile_diagnostics`, which **is** a plugin (Android/iOS native).  
`flutter_network_core` should **not** copy that template.

- No `android/` / `ios/` folders required for v1.
- `pubspec.yaml`: Dart package with `dio`, `connectivity_plus`, optionally `flutter_secure_storage`.
- Works on **Flutter mobile, Flutter web, and Dart VM** (server/CLI) if connectivity is abstracted.

If you later want a native “is internet really reachable” probe, that small piece can become a plugin dependency — still not the HTTP layer itself.

---

## 10. Risks and design rules

| Risk | Rule |
|------|------|
| Every backend uses different refresh JSON | Never hardcode refresh URL/body; use `TokenRefreshDelegate` |
| Concurrent 401 refresh storms | `QueuedInterceptor` + single in-flight refresh |
| Refresh interceptor calling itself | Separate plain Dio instance |
| Package too opinionated (Either vs throw) | Support **typed throws** first; optional `ApiResult<T>` later |
| Logging leaks tokens in production | Logger only in debug; redact Authorization |
| Multipart retry after 401 | Rebuild `FormData` on retry (Dio gotcha) |
| Existing pub packages (`dio_architect`, `advanced_api_client`) | Similar ideas exist; a **private/internal** package still pays off if you control exceptions and API to match your team |

---

## 11. Proposed public API (v1)

```dart
class NetworkConfig { ... }

class NetworkClient {
  Future<T> get<T>(String path, {query, headers, CancelToken?});
  Future<T> post<T>(String path, {data, query, headers, CancelToken?});
  Future<T> put<T>(...);
  Future<T> patch<T>(...);
  Future<T> delete<T>(...);
  Future<T> upload<T>(String path, {FormData, onSendProgress});
  Future<void> download(String url, String savePath, {onReceiveProgress});
}

class TokenPair {
  final String accessToken;
  final String refreshToken;
}

abstract class TokenStorage { ... }
abstract class TokenRefreshDelegate { ... }

sealed class AppNetworkException implements Exception { ... }
```

---

## 12. Suggested implementation phases

| Phase | Deliverable |
|-------|-------------|
| **0 — this doc** | Feasibility + design (done) |
| **1 — skeleton package** | `pubspec`, barrel, `NetworkConfig`, `NetworkClient` methods, exception types + mapper |
| **2 — interceptors** | Auth + queued refresh + connectivity + retry + log |
| **3 — adapters** | Default `SecureTokenStorage`, example `TokenRefreshDelegate` |
| **4 — example app** | Login, authenticated GET, forced 401, offline, timeout |
| **5 — tests** | Mapper unit tests, refresh queue tests (mock Dio adapter) |
| **6 — publish** | Private Git + optional pub.dev |

Phase 1–4 is enough to stop rewriting this in every project.

---

## 13. Conclusion

| Question | Answer |
|----------|--------|
| Can we avoid writing Dio + interceptors + exceptions in every project? | **Yes** |
| Should it be a Flutter **plugin** (platform channels)? | **No** — use a **package** |
| Can access + refresh tokens live in interceptors? | **Yes**, with queued refresh and a second Dio for refresh |
| Can all exception types be global? | **Yes**, if 401 is split into auth-fail vs session-expired |
| Will the app still write any network code? | **Yes** — only feature repositories and refresh JSON mapping |

**Recommendation:** create `flutter_network_core` as a Dart package in this folder, implement Phase 1–4, then depend on it from every Flutter app (`flutter_network_core: path:` or Git).

This analysis does **not** implement the package yet. Next step is scaffolding `pubspec.yaml` and the exception + client skeleton when you want to build it.
