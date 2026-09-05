import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_network_core/flutter_network_core.dart';

void main() {
  runApp(const NetworkCoreExampleApp());
}

class NetworkCoreExampleApp extends StatefulWidget {
  const NetworkCoreExampleApp({super.key});

  @override
  State<NetworkCoreExampleApp> createState() => _NetworkCoreExampleAppState();
}

class _NetworkCoreExampleAppState extends State<NetworkCoreExampleApp> {
  late final MockApiAdapter _adapter;
  late final MemoryTokenStorage _storage;
  late final ManualConnectivityChecker _connectivity;
  late final NetworkClient _network;
  final _log = <String>[];
  var _pending = 0;
  var _sessionExpired = false;
  var _online = true;

  @override
  void initState() {
    super.initState();
    _adapter = MockApiAdapter();
    _storage = MemoryTokenStorage();
    _connectivity = ManualConnectivityChecker();
    _network = NetworkClient(
      config: NetworkConfig(
        baseUrl: 'https://api.example.com',
        enableLogging: false,
        retry: const RetryConfig(maxExtraAttempts: 0),
      ),
      tokenStorage: _storage,
      connectivity: _connectivity,
      httpClientAdapter: _adapter,
      usePluginConnectivity: false,
      refreshDelegateBuilder: (plain) => HttpTokenRefreshDelegate(
        client: plain,
        path: '/auth/refresh',
        bodyBuilder: (token) => {'refreshToken': token},
        parser: (data) {
          final map = Map<String, dynamic>.from(data as Map);
          return TokenPair(
            accessToken: map['accessToken'] as String,
            refreshToken: map['refreshToken'] as String,
          );
        },
      ),
      onSessionExpired: () {
        setState(() => _sessionExpired = true);
        _append('SessionExpiredException → sign in again');
      },
    );
    _network.pendingRequestCount.listen((count) {
      if (mounted) {
        setState(() => _pending = count);
      }
    });
  }

  @override
  void dispose() {
    _network.close();
    _connectivity.dispose();
    super.dispose();
  }

  void _append(String line) {
    setState(() => _log.insert(0, line));
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    _append('▶ $label');
    try {
      await action();
    } on AppNetworkException catch (error) {
      _append('✖ ${error.runtimeType}: ${error.message}');
    } catch (error) {
      _append('✖ $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_network_core',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('flutter_network_core'),
          actions: [
            if (_pending > 0)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            if (_sessionExpired)
              const MaterialBanner(
                content: Text('Session expired'),
                actions: [SizedBox.shrink()],
              ),
            SwitchListTile(
              title: const Text('Online'),
              value: _online,
              onChanged: (value) {
                _connectivity.setOnline(value);
                setState(() => _online = value);
                _append(value ? 'Connectivity: online' : 'Connectivity: offline');
              },
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () => _run('Login', () async {
                    _sessionExpired = false;
                    final data =
                        await _network.unauthenticated.post<Map<String, dynamic>>(
                      '/auth/login',
                      data: {'email': 'user@example.com', 'password': 'secret'},
                    );
                    await _storage.write(
                      TokenPair(
                        accessToken: data['accessToken'] as String,
                        refreshToken: data['refreshToken'] as String,
                      ),
                    );
                    _append('Logged in');
                  }),
                  child: const Text('Login'),
                ),
                FilledButton.tonal(
                  onPressed: () => _run('GET /users/me', () async {
                    final data = await _network.get<Map<String, dynamic>>(
                      '/users/me',
                    );
                    _append('Hello ${data['name']}');
                  }),
                  child: const Text('Profile'),
                ),
                OutlinedButton(
                  onPressed: () {
                    _adapter.expireAccessToken();
                    _append('Access token marked expired (next call 401)');
                  },
                  child: const Text('Force 401'),
                ),
                OutlinedButton(
                  onPressed: () {
                    _adapter.killRefresh();
                    _append('Refresh endpoint will fail');
                  },
                  child: const Text('Kill refresh'),
                ),
                OutlinedButton(
                  onPressed: () => _run('Forbidden', () async {
                    await _network.get<Map<String, dynamic>>('/admin');
                  }),
                  child: const Text('403'),
                ),
                OutlinedButton(
                  onPressed: () => _run('Bad login', () async {
                    await _network.unauthenticated.post<Map<String, dynamic>>(
                      '/auth/login',
                      data: {'email': 'x', 'password': 'wrong'},
                    );
                  }),
                  child: const Text('Bad login'),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _log.length,
                itemBuilder: (context, index) => Text(_log[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MockApiAdapter implements HttpClientAdapter {
  var _accessValid = true;
  var _refreshValid = true;
  var _issued = 0;

  void expireAccessToken() => _accessValid = false;

  void killRefresh() => _refreshValid = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path.endsWith('/auth/login')) {
      final body = await _readJson(requestStream);
      if (body['password'] != 'secret') {
        return _json({'message': 'invalid credentials'}, 401);
      }
      _accessValid = true;
      _refreshValid = true;
      _issued += 1;
      return _json({
        'accessToken': 'access-$_issued',
        'refreshToken': 'refresh-$_issued',
      });
    }
    if (path.endsWith('/auth/refresh')) {
      if (!_refreshValid) {
        return _json({'message': 'refresh expired'}, 401);
      }
      _accessValid = true;
      _issued += 1;
      return _json({
        'accessToken': 'access-$_issued',
        'refreshToken': 'refresh-$_issued',
      });
    }
    if (path.endsWith('/admin')) {
      return _json({'message': 'forbidden'}, 403);
    }
    if (path.endsWith('/users/me')) {
      final auth = options.headers['Authorization'] as String?;
      if (auth == null || !_accessValid) {
        return _json({'message': 'expired'}, 401);
      }
      return _json({'name': 'Ghanashyam', 'token': auth});
    }
    return _json({'message': 'not found'}, 404);
  }

  @override
  void close({bool force = false}) {}

  Future<Map<String, dynamic>> _readJson(Stream<Uint8List>? stream) async {
    if (stream == null) {
      return {};
    }
    final chunks = await stream.toList();
    if (chunks.isEmpty) {
      return {};
    }
    final bytes = chunks.expand((chunk) => chunk).toList();
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  ResponseBody _json(Object data, [int status = 200]) {
    return ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
