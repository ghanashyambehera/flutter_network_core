import 'dart:async';

import '../exceptions/app_network_exception.dart';

enum NetworkEventKind { start, end, error }

class NetworkEvent {
  const NetworkEvent({
    required this.kind,
    required this.path,
    this.error,
  });

  final NetworkEventKind kind;
  final String path;
  final AppNetworkException? error;
}

class RequestLifecycle {
  RequestLifecycle();

  int _pending = 0;
  final _pendingController = StreamController<int>.broadcast();
  final _eventController = StreamController<NetworkEvent>.broadcast();

  int get pendingCountValue => _pending;
  Stream<int> get pendingCount => _pendingController.stream;
  Stream<NetworkEvent> get events => _eventController.stream;

  void start(String path) {
    if (_pendingController.isClosed) {
      return;
    }
    _pending += 1;
    _pendingController.add(_pending);
    _eventController.add(NetworkEvent(kind: NetworkEventKind.start, path: path));
  }

  void end(String path) {
    if (_pendingController.isClosed) {
      return;
    }
    _pending = _pending > 0 ? _pending - 1 : 0;
    _pendingController.add(_pending);
    _eventController.add(NetworkEvent(kind: NetworkEventKind.end, path: path));
  }

  void error(String path, AppNetworkException exception) {
    if (_eventController.isClosed) {
      return;
    }
    _eventController.add(
      NetworkEvent(kind: NetworkEventKind.error, path: path, error: exception),
    );
  }

  void close() {
    _pendingController.close();
    _eventController.close();
  }
}
