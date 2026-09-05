import 'package:flutter/foundation.dart';

import 'network_logger.dart';

class DebugPrintLogger implements NetworkLogger {
  const DebugPrintLogger();

  @override
  void log(String message) => debugPrint(message);
}

class NoOpLogger implements NetworkLogger {
  const NoOpLogger();

  @override
  void log(String message) {}
}

class CollectingLogger implements NetworkLogger {
  final List<String> lines = [];

  @override
  void log(String message) => lines.add(message);
}
