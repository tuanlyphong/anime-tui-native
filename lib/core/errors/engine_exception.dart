import 'dart:async';
import 'dart:io';

/// Stable error categories surfaced by the engine layer.
///
/// The UI maps each kind to a human-readable message and an actionable hint,
/// while the raw engine stderr is preserved for the logs screen.
enum EngineErrorKind {
  unsupportedPlatform,
  notConfigured,
  nodeNotFound,
  spawnFailed,
  network,
  timeout,
  cancelled,
  busy,
  exitFailure,
  protocol,
  parse,
}

class EngineException implements Exception {
  EngineException(
    this.kind,
    this.message, {
    this.details,
    this.exitCode,
    this.command,
    this.cause,
    this.stackTrace,
  });

  final EngineErrorKind kind;

  /// Technical description (shown in logs and expandable details).
  final String message;

  /// Engine stderr, if any.
  final String? details;
  final int? exitCode;
  final String? command;
  final Object? cause;
  final StackTrace? stackTrace;

  factory EngineException.from(
    Object error, {
    StackTrace? stackTrace,
    String? command,
  }) {
    if (error is EngineException) return error;
    if (error is ProcessException) {
      return EngineException(
        EngineErrorKind.spawnFailed,
        'Could not start the engine process: ${error.message}',
        details: error.toString(),
        cause: error,
        stackTrace: stackTrace,
        command: command,
      );
    }
    if (error is SocketException) {
      return EngineException(
        EngineErrorKind.network,
        'Could not reach the site: ${error.message}',
        details: error.toString(),
        cause: error,
        stackTrace: stackTrace,
        command: command,
      );
    }
    if (error is TimeoutException) {
      return EngineException(
        EngineErrorKind.timeout,
        'The engine did not respond in time.',
        cause: error,
        stackTrace: stackTrace,
        command: command,
      );
    }
    return EngineException(
      EngineErrorKind.spawnFailed,
      error.toString(),
      cause: error,
      stackTrace: stackTrace,
      command: command,
    );
  }

  /// Short, non-technical sentence suitable for a snackbar or empty state.
  String get userMessage => switch (kind) {
        EngineErrorKind.unsupportedPlatform =>
          'The engine requires Node.js, which is only available on desktop.',
        EngineErrorKind.notConfigured =>
          'The anime engine is not configured yet.',
        EngineErrorKind.nodeNotFound =>
          'Node.js could not be found on this computer.',
        EngineErrorKind.spawnFailed => 'The engine could not be started.',
        EngineErrorKind.network =>
          'The anime site could not be reached. Check your connection or VPN and try again.',
        EngineErrorKind.timeout =>
          'The engine took too long to respond. The site may be slow or blocked.',
        EngineErrorKind.cancelled => 'The request was cancelled.',
        EngineErrorKind.busy => 'The engine is busy. Try again in a moment.',
        EngineErrorKind.exitFailure =>
          'The engine reported an error while running the command.',
        EngineErrorKind.protocol =>
          'The engine returned an unexpected response. It may be an incompatible version.',
        EngineErrorKind.parse =>
          'The engine response could not be read. See the logs for details.',
      };

  /// Concrete next step for the user.
  String get hint => switch (kind) {
        EngineErrorKind.unsupportedPlatform =>
          'Run the app on Windows, macOS, or Linux.',
        EngineErrorKind.notConfigured =>
          'Open Settings to configure the engine (anime.js and, for Abyss streams, abyss-dl.jar), or set ANIME_TUI_ENGINE_PATH / ABYSS_DL_JAR.',
        EngineErrorKind.nodeNotFound =>
          'Install Node.js 18+ or set ANIME_TUI_NODE to the node executable.',
        EngineErrorKind.spawnFailed =>
          'Check the engine path and file permissions in Settings.',
        EngineErrorKind.network =>
          'Check the internet connection, VPN/proxy settings, and try again.',
        EngineErrorKind.timeout => 'Check your network/VPN and try again.',
        EngineErrorKind.cancelled => 'Retry the action when ready.',
        EngineErrorKind.busy => 'Wait for the running command to finish.',
        EngineErrorKind.exitFailure =>
          'Check the Logs tab for the engine error output.',
        EngineErrorKind.protocol =>
          'Make sure the engine matches the command set documented in the README.',
        EngineErrorKind.parse => 'Check the Logs tab for the raw output.',
      };

  @override
  String toString() {
    final buffer = StringBuffer('EngineException(${kind.name}): $message');
    if (exitCode != null) buffer.write(' [exit $exitCode]');
    if (details != null && details!.trim().isNotEmpty) {
      buffer.write('\n$details');
    }
    return buffer.toString();
  }
}
