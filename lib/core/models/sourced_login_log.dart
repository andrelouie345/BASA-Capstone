// lib/core/models/sourced_login_log.dart
import 'login_log.dart';

enum LogSource { local, cloud }

/// A login attempt plus where it was found. Online attempts are written to
/// both stores, so the same attempt usually shows up with both sources.
class SourcedLoginLog {
  final LoginLog log;
  final Set<LogSource> sources;

  const SourcedLoginLog(this.log, this.sources);

  /// "local", "cloud" or "local+cloud".
  String get sourceLabel => LogSource.values.where(sources.contains).map((s) => s.name).join('+');
}
