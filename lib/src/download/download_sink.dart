abstract class DownloadSink {
  bool get supportsPath;

  Future<void> save(List<int> bytes, String suggestedNameOrPath);
}
