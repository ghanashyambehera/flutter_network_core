import 'token_pair.dart';

/// App-owned refresh call. Must use the plain (unauthenticated) Dio client.
abstract class TokenRefreshDelegate {
  Future<TokenPair> refresh(String refreshToken);
}
