// lib/core/console/logger.dart
abstract class Logger {
  void log(String source, String message);
}

/// Bound to one ViewModel's name so call sites just do `_log('did a thing')`.
class ScopedLogger {
  final Logger? _logger;
  final String source;
  ScopedLogger(this._logger, this.source);

  void call(String message) => _logger?.log(source, message);
}