import 'package:connectivity_plus/connectivity_plus.dart';

import '../../connectivity/connectivity_checker.dart';

class ConnectivityPlusChecker implements ConnectivityChecker {
  ConnectivityPlusChecker({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> get isOnline async {
    final results = await _connectivity.checkConnectivity();
    return _hasLink(results);
  }

  @override
  Stream<bool> get onChanged =>
      _connectivity.onConnectivityChanged.map(_hasLink);

  bool _hasLink(List<ConnectivityResult> results) {
    if (results.isEmpty) {
      return false;
    }
    return results.any((result) => result != ConnectivityResult.none);
  }
}
