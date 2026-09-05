import 'package:meta/meta.dart';

@immutable
class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;

  bool get isEmpty => accessToken.isEmpty && refreshToken.isEmpty;
}
