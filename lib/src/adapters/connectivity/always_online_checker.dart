import 'dart:async';

import '../../connectivity/connectivity_checker.dart';

class AlwaysOnlineChecker implements ConnectivityChecker {
  const AlwaysOnlineChecker();

  @override
  Future<bool> get isOnline async => true;

  @override
  Stream<bool> get onChanged => const Stream.empty();
}

class ManualConnectivityChecker implements ConnectivityChecker {
  ManualConnectivityChecker({bool online = true}) : _online = online;

  bool _online;
  final _controller = StreamController<bool>.broadcast();

  @override
  Future<bool> get isOnline async => _online;

  @override
  Stream<bool> get onChanged => _controller.stream;

  void setOnline(bool value) {
    _online = value;
    _controller.add(value);
  }

  void dispose() => _controller.close();
}
