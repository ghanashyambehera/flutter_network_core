import 'token_pair.dart';

abstract class TokenStorage {
  Future<TokenPair?> read();
  Future<void> write(TokenPair pair);
  Future<void> clear();
}
