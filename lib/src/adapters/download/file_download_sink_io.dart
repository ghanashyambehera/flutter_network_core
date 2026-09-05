import 'dart:io';

import '../../download/download_sink.dart';

class FileDownloadSink implements DownloadSink {
  const FileDownloadSink();

  @override
  bool get supportsPath => true;

  @override
  Future<void> save(List<int> bytes, String suggestedNameOrPath) async {
    final file = File(suggestedNameOrPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }
}
