import 'package:flutter_network_core/flutter_network_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/scripted_adapter.dart';

NetworkClient buildClient({
  required ScriptedAdapter adapter,
  TokenStorage? storage,
  TokenRefreshDelegate Function(dynamic plain)? refreshBuilder,
  ConnectivityChecker? connectivity,
  void Function()? onSessionExpired,
  RetryConfig retry = const RetryConfig(maxExtraAttempts: 0),
}) {
  return NetworkClient(
    config: NetworkConfig(
      baseUrl: 'https://api.test',
      retry: retry,
      enableLogging: false,
    ),
    tokenStorage: storage ?? MemoryTokenStorage(),
    connectivity: connectivity ?? const AlwaysOnlineChecker(),
    httpClientAdapter: adapter,
    onSessionExpired: onSessionExpired,
    refreshDelegateBuilder: refreshBuilder == null
        ? null
        : (plain) => refreshBuilder(plain),
    usePluginConnectivity: false,
  );
}

void main() {
  test('GET returns JSON on success', () async {
    final adapter = ScriptedAdapter((options) async {
      expect(options.method, 'GET');
      return jsonResponse({'id': 1});
    });
    final client = buildClient(adapter: adapter);

    final data = await client.get<Map<String, dynamic>>('/users/1');
    expect(data['id'], 1);
    client.close();
  });

  test('offline connectivity throws NetworkException', () async {
    final adapter = ScriptedAdapter((options) async {
      fail('HTTP should not run while offline');
    });
    final client = buildClient(
      adapter: adapter,
      connectivity: ManualConnectivityChecker(online: false),
    );

    await expectLater(
      client.get<Map<String, dynamic>>('/users/1'),
      throwsA(isA<NetworkException>()),
    );
    expect(adapter.fetchCount, 0);
    client.close();
  });

  test('public login 401 is AuthenticationException', () async {
    final adapter = ScriptedAdapter((options) async {
      return jsonResponse({'message': 'invalid'}, status: 401);
    });
    final client = buildClient(adapter: adapter);

    await expectLater(
      client.unauthenticated.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': 'a', 'password': 'b'},
      ),
      throwsA(isA<AuthenticationException>()),
    );
    client.close();
  });

  test('403 is AuthorizationException', () async {
    final adapter = ScriptedAdapter((options) async {
      return jsonResponse({'message': 'nope'}, status: 403);
    });
    final client = buildClient(adapter: adapter);

    await expectLater(
      client.get<Map<String, dynamic>>('/admin'),
      throwsA(isA<AuthorizationException>()),
    );
    client.close();
  });

  test('refresh is single-flight then original requests succeed', () async {
    var refreshCount = 0;
    final storage = MemoryTokenStorage(
      const TokenPair(accessToken: 'old', refreshToken: 'r1'),
    );
    final adapter = ScriptedAdapter((options) async {
      if (options.path.contains('refresh')) {
        refreshCount += 1;
        return jsonResponse({
          'accessToken': 'new',
          'refreshToken': 'r2',
        });
      }
      final auth = options.headers['Authorization'] as String?;
      if (auth == 'Bearer new') {
        return jsonResponse({'ok': true});
      }
      return jsonResponse({'message': 'expired'}, status: 401);
    });

    final client = buildClient(
      adapter: adapter,
      storage: storage,
      refreshBuilder: (plain) => HttpTokenRefreshDelegate(
        client: plain,
        path: '/auth/refresh',
        bodyBuilder: (token) => {'refreshToken': token},
        parser: (data) {
          final map = data as Map<String, dynamic>;
          return TokenPair(
            accessToken: map['accessToken'] as String,
            refreshToken: map['refreshToken'] as String,
          );
        },
      ),
    );

    final results = await Future.wait([
      client.get<Map<String, dynamic>>('/me'),
      client.get<Map<String, dynamic>>('/me'),
      client.get<Map<String, dynamic>>('/me'),
    ]);

    expect(results.every((row) => row['ok'] == true), isTrue);
    expect(refreshCount, 1);
    expect((await storage.read())?.accessToken, 'new');
    client.close();
  });

  test('failed refresh throws SessionExpiredException once', () async {
    var expired = 0;
    final storage = MemoryTokenStorage(
      const TokenPair(accessToken: 'old', refreshToken: 'r1'),
    );
    final adapter = ScriptedAdapter((options) async {
      if (options.path.contains('refresh')) {
        return jsonResponse({'message': 'dead'}, status: 401);
      }
      return jsonResponse({'message': 'expired'}, status: 401);
    });

    final client = buildClient(
      adapter: adapter,
      storage: storage,
      onSessionExpired: () => expired += 1,
      refreshBuilder: (plain) => HttpTokenRefreshDelegate(
        client: plain,
        path: '/auth/refresh',
        bodyBuilder: (token) => {'refreshToken': token},
        parser: (data) {
          final map = data as Map<String, dynamic>;
          return TokenPair(
            accessToken: map['accessToken'] as String,
            refreshToken: map['refreshToken'] as String,
          );
        },
      ),
    );

    await expectLater(
      client.get<Map<String, dynamic>>('/me'),
      throwsA(isA<SessionExpiredException>()),
    );
    expect(expired, 1);
    expect(await storage.read(), isNull);
    client.close();
  });

  test('retries 503 then succeeds', () async {
    var hits = 0;
    final adapter = ScriptedAdapter((options) async {
      hits += 1;
      if (hits < 3) {
        return jsonResponse({'message': 'busy'}, status: 503);
      }
      return jsonResponse({'ok': true});
    });
    final client = buildClient(
      adapter: adapter,
      retry: const RetryConfig(
        maxExtraAttempts: 3,
        initialBackoff: Duration.zero,
      ),
    );

    final data = await client.get<Map<String, dynamic>>('/flaky');
    expect(data['ok'], true);
    expect(hits, 3);
    client.close();
  });
}
