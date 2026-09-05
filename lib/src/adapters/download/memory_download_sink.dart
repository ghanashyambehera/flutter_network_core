import '../../download/download_sink.dart';

class MemoryDownloadSink implements DownloadSink {
  final Map<String, List<int>> files = {};

  @override
  bool get supportsPath => true;

  @override
  Future<void> save(List<int> bytes, String suggestedNameOrPath) async {
    files[suggestedNameOrPath] = List<int>.from(bytes);
  }
}

class UnsupportedDownloadSink implements DownloadSink {
  const UnsupportedDownloadSink();

  @override
  bool get supportsPath => false;

  @override
  Future<void> save(List<int> bytes, String suggestedNameOrPath) {
    throw UnsupportedError(
      'Path downloads are not available on this platform. Use downloadBytes().',
    );
  }
}
