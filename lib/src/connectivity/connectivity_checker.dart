abstract class ConnectivityChecker {
  Future<bool> get isOnline;
  Stream<bool> get onChanged;
}
