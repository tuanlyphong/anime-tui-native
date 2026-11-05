import 'dart:async';

import 'engine_command.dart';
import 'models.dart';

/// One running engine process.
class EngineRun {
  EngineRun({
    required this.id,
    required this.command,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.stop,
    required this.startedAt,
  });

  final String id;
  final EngineCommand command;

  /// Decoded, line-split output. Empty lines are filtered by the client.
  final Stream<String> stdout;
  final Stream<String> stderr;
  final Future<int> exitCode;

  /// Sends SIGTERM (then SIGKILL after a grace period on POSIX).
  final Future<void> Function() stop;
  final DateTime startedAt;

  Duration get elapsed => DateTime.now().difference(startedAt);
}

/// Abstraction over "how commands reach the engine".
///
/// The current implementation launches one CLI process per command. A future
/// JSON-lines daemon can implement this interface without touching controllers
/// or UI code.
abstract interface class EngineTransport {
  Future<EngineRun> start(EngineCommand command);

  Future<EngineHealth> healthCheck();

  Future<void> dispose();
}
