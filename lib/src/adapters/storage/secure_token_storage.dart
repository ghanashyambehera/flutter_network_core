import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../auth/token_pair.dart';
import '../../auth/token_storage.dart';

/// Uses platform secure storage (Keychain / Keystore / DPAPI / WebCrypto).
///
/// On web, persistence is weaker than on mobile. Prefer httpOnly cookies if
/// the backend supports them.
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage({
    FlutterSecureStorage? storage,
    this.accessKey = 'fnc_access_token',
    this.refreshKey = 'fnc_refresh_token',
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final String accessKey;
  final String refreshKey;

  @override
  Future<TokenPair?> read() async {
    final access = await _storage.read(key: accessKey);
    final refresh = await _storage.read(key: refreshKey);
    if (access == null || refresh == null) {
      return null;
    }
    return TokenPair(accessToken: access, refreshToken: refresh);
  }

  @override
  Future<void> write(TokenPair pair) async {
    await _storage.write(key: accessKey, value: pair.accessToken);
    await _storage.write(key: refreshKey, value: pair.refreshToken);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: accessKey);
    await _storage.delete(key: refreshKey);
  }
}
