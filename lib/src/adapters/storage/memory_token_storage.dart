import '../../auth/token_pair.dart';
import '../../auth/token_storage.dart';

class MemoryTokenStorage implements TokenStorage {
  MemoryTokenStorage([this._pair]);

  TokenPair? _pair;

  @override
  Future<TokenPair?> read() async => _pair;

  @override
  Future<void> write(TokenPair pair) async {
    _pair = pair;
  }

  @override
  Future<void> clear() async {
    _pair = null;
  }
}
