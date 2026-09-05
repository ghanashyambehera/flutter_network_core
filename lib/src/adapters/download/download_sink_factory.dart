import '../../download/download_sink.dart';
import 'download_sink_stub.dart'
    if (dart.library.io) 'download_sink_io.dart'
    if (dart.library.js_interop) 'download_sink_web.dart' as impl;

DownloadSink createDefaultDownloadSink() => impl.createDefaultDownloadSink();
