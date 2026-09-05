import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this.onFetch);

  final Future<ResponseBody> Function(RequestOptions options) onFetch;
  int fetchCount = 0;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount += 1;
    requests.add(options);
    return onFetch(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object data, {int status = 200}) {
  return ResponseBody.fromString(
    jsonEncode(data),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

ResponseBody emptyResponse({int status = 204}) {
  return ResponseBody.fromString('', status);
}
