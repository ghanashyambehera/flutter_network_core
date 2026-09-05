import 'package:dio/dio.dart';
import 'package:flutter_network_core/src/exceptions/exception_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_network_core/flutter_network_core.dart';

void main() {
  const mapper = ExceptionMapper();

  RequestOptions options({String path = '/x'}) =>
      RequestOptions(path: path, baseUrl: 'https://api.test/');

  test('maps connection errors to NetworkException', () {
    final mapped = mapper.map(
      DioException(
        requestOptions: options(),
        type: DioExceptionType.connectionError,
      ),
    );
    expect(mapped, isA<NetworkException>());
  });

  test('maps timeouts to NetworkTimeoutException', () {
    final mapped = mapper.map(
      DioException(
        requestOptions: options(),
        type: DioExceptionType.receiveTimeout,
      ),
    );
    expect(mapped, isA<NetworkTimeoutException>());
  });

  test('maps public 401 to AuthenticationException', () {
    final mapped = mapper.map(
      DioException(
        requestOptions: options(path: '/login'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: options(path: '/login'),
          statusCode: 401,
          data: {'message': 'bad password'},
        ),
      ),
      isPublic: true,
    );
    expect(mapped, isA<AuthenticationException>());
    expect(mapped.message, 'bad password');
  });

  test('maps protected 401 to SessionExpiredException', () {
    final mapped = mapper.map(
      DioException(
        requestOptions: options(path: '/me'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: options(path: '/me'),
          statusCode: 401,
        ),
      ),
    );
    expect(mapped, isA<SessionExpiredException>());
  });

  test('maps 403 to AuthorizationException', () {
    final mapped = mapper.map(
      DioException(
        requestOptions: options(),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: options(),
          statusCode: 403,
        ),
      ),
    );
    expect(mapped, isA<AuthorizationException>());
  });

  test('maps 5xx to ServerException', () {
    final mapped = mapper.map(
      DioException(
        requestOptions: options(),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: options(),
          statusCode: 502,
        ),
      ),
    );
    expect(mapped, isA<ServerException>());
    expect(mapped.statusCode, 502);
  });

  test('maps other 4xx to ClientException', () {
    final mapped = mapper.map(
      DioException(
        requestOptions: options(),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: options(),
          statusCode: 404,
          data: {'detail': 'missing'},
        ),
      ),
    );
    expect(mapped, isA<ClientException>());
    expect(mapped.message, 'missing');
  });

  test('maps cancel to CancelledException', () {
    final mapped = mapper.map(
      DioException(
        requestOptions: options(),
        type: DioExceptionType.cancel,
      ),
    );
    expect(mapped, isA<CancelledException>());
  });

  test('unwraps AppNetworkException already on DioException.error', () {
    const original = NetworkException(message: 'offline');
    final mapped = mapper.map(
      DioException(
        requestOptions: options(),
        type: DioExceptionType.unknown,
        error: original,
      ),
    );
    expect(mapped, same(original));
  });
}
