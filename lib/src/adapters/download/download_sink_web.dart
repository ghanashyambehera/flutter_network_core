import '../../download/download_sink.dart';

/// Path downloads are not supported in the default web adapter.
/// Use [NetworkClient.downloadBytes] or inject a custom [DownloadSink].
class BrowserDownloadSink implements DownloadSink {
  const BrowserDownloadSink();

  @override
  bool get supportsPath => false;

  @override
  Future<void> save(List<int> bytes, String suggestedNameOrPath) {
    throw UnsupportedError(
      'Path downloads are not available on web. Use downloadBytes(), '
      'then save with a custom DownloadSink if you need a file prompt.',
    );
  }
}

DownloadSink createDefaultDownloadSink() => const BrowserDownloadSink();
