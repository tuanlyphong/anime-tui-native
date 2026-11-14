import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/errors/engine_exception.dart';
import '../core/logging/app_logger.dart';
import 'engine_command.dart';
import 'engine_config.dart';
import 'engine_transport.dart';
import 'java_runtime.dart';
import 'models.dart';

/// Launches one `node anime.js <command>` process per request.
///
/// This matches the real engine contract. The previous implementation spawned
/// the CLI once and wrote commands to its stdin, but `anime.js` exits
/// immediately after reading `process.argv` — so nothing was ever executed.
class CliEngineTransport implements EngineTransport {
  CliEngineTransport({
    required this.config,
    AppLogger? logger,
  }) : _logger = logger ?? AppLogger.instance;

  final EngineConfig config;
  final AppLogger _logger;

  final Map<String, Process> _live = <String, Process>{};
  int _nextId = 0;
  bool _disposed = false;

  @override
  Future<EngineRun> start(EngineCommand command) async {
    if (_disposed) {
      throw EngineException(
        EngineErrorKind.cancelled,
        'The engine client has been disposed.',
      );
    }
    if (!config.isSupportedPlatform) {
      throw EngineException(
        EngineErrorKind.unsupportedPlatform,
        'The Node.js engine cannot run on ${Platform.operatingSystem}.',
      );
    }
    if (config.scriptPath.isEmpty) {
      throw EngineException(
        EngineErrorKind.notConfigured,
        'No engine script is configured.',
      );
    }
    if (!File(config.scriptPath).existsSync()) {
      throw EngineException(
        EngineErrorKind.notConfigured,
        'Engine script not found.',
        details: 'Looked for ${config.scriptPath}',
        command: command.label,
      );
    }

    final id = 'engine-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';
    final stopwatch = Stopwatch()..start();

    Process process;
    try {
      process = await Process.start(
        config.nodeExecutable,
        <String>[config.scriptPath, ...command.arguments],
        workingDirectory: config.workingDirectory,
        environment: config.environment,
        includeParentEnvironment: true,
        runInShell: false,
      );
    } on ProcessException catch (error, stackTrace) {
      final kind = error.errorCode == 2 /* ENOENT */
          ? EngineErrorKind.nodeNotFound
          : EngineErrorKind.spawnFailed;
      _logger.error(
        'Engine process failed to start',
        error: error,
        stackTrace: stackTrace,
        context: {
          'command': command.label,
          'node': config.nodeExecutable,
          'script': config.scriptPath,
        },
      );
      throw EngineException(
        kind,
        'Could not start Node.js (${config.nodeExecutable}).',
        details: error.message,
        cause: error,
        stackTrace: stackTrace,
        command: command.label,
      );
    }

    _live[id] = process;
    _logger.info(
      'Engine command started',
      context: {
        'id': id,
        'command': command.label,
        'node': config.nodeExecutable,
      },
    );

    // Broadcast so callers (and any future logging tap) may listen more
    // than once without tripping "Stream has already been listened to".
    // EngineClient still attaches its single listener immediately after
    // start() returns, before the engine produces any output, so no early
    // lines are lost and the pipe is drained concurrently with the process
    // (waiting for exitCode before draining would risk a pipe stall).
    final stdout = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .asBroadcastStream();
    final stderr = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .asBroadcastStream();

    final exitCode = process.exitCode.then((code) {
      _live.remove(id);
      _logger.info(
        'Engine command exited',
        context: {
          'id': id,
          'command': command.label,
          'exit': code,
          'ms': stopwatch.elapsedMilliseconds,
        },
      );
      return code;
    });

    return EngineRun(
      id: id,
      command: command,
      stdout: stdout,
      stderr: stderr,
      exitCode: exitCode,
      startedAt: DateTime.now(),
      stop: () => _terminate(process, id, command),
    );
  }

  Future<void> _terminate(
    Process process,
    String id,
    EngineCommand command,
  ) async {
    // Dart's Process.kill only terminates the direct child. The engine starts
    // mpv and Java descendants, so Windows needs taskkill /T to stop the whole
    // tree; killing Node alone would leave a player running.
    if (Platform.isWindows) {
      _logger.warning(
        'Stopping engine command tree',
        context: {'id': id, 'command': command.label},
      );
      if (process.pid > 0) {
        try {
          await Process.run(
            'taskkill',
            <String>['/PID', '${process.pid}', '/T', '/F'],
            runInShell: false,
            stdoutEncoding: utf8,
            stderrEncoding: utf8,
          ).timeout(const Duration(seconds: 5));
        } on Object catch (error) {
          _logger.warning(
            'taskkill failed; falling back to Process.kill',
            error: error,
            context: {'id': id, 'pid': process.pid},
          );
          try {
            process.kill(ProcessSignal.sigkill);
          } on Object {
            // Process may already be gone.
          }
        }
      }
      await Future.any(<Future<void>>[
        process.exitCode.then((_) {}),
        Future<void>.delayed(const Duration(seconds: 3)),
      ]);
      _live.remove(id);
      return;
    }

    var exited = false;
    unawaited(process.exitCode.then(
      (_) {
        exited = true;
      },
      onError: (Object _) {
        exited = true;
      },
    ));

    if (!exited) {
      _logger.warning(
        'Stopping engine command',
        context: {'id': id, 'command': command.label},
      );
      try {
        process.kill(ProcessSignal.sigterm);
      } on Object {
        // Windows does not implement SIGTERM; fall through to SIGKILL.
      }

      await Future.any(<Future<void>>[
        process.exitCode.then((_) {}),
        Future<void>.delayed(const Duration(seconds: 3)),
      ]);
    }

    if (!exited) {
      try {
        process.kill(ProcessSignal.sigkill);
      } on Object {
        // Process may already be gone.
      }
      await Future.any(<Future<void>>[
        process.exitCode.then((_) {}),
        Future<void>.delayed(const Duration(seconds: 2)),
      ]);
    }
    _live.remove(id);
  }

  @override
  Future<EngineHealth> healthCheck() async {
    if (!config.isSupportedPlatform) {
      return EngineHealth.unavailable(
        'The Node.js engine requires Windows, macOS, or Linux. '
        'This build is running on ${Platform.operatingSystem}.',
        enginePath: config.scriptPath,
      );
    }
    if (config.scriptPath.isEmpty) {
      return EngineHealth.unavailable(
        'No engine script configured. Open Settings to choose anime.js.',
      );
    }
    if (!File(config.scriptPath).existsSync()) {
      return EngineHealth.unavailable(
        'Engine script not found at ${config.scriptPath}',
        enginePath: config.scriptPath,
      );
    }

    try {
      final result = await Process.run(
        config.nodeExecutable,
        <String>['--version'],
        environment: config.environment,
        includeParentEnvironment: true,
        runInShell: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 8));

      if (result.exitCode != 0) {
        return EngineHealth.unavailable(
          'Node.js is not runnable: ${result.stderr.toString().trim()}',
          enginePath: config.scriptPath,
        );
      }

      final version = result.stdout.toString().trim();
      final major = int.tryParse(
        RegExp(r'v?(\d+)').firstMatch(version)?.group(1) ?? '',
      );
      if (major != null && major < 18) {
        return EngineHealth.unavailable(
          'Node.js 18+ is required; found $version.',
          enginePath: config.scriptPath,
        );
      }

      // Surface a Java mismatch during startup/settings tests instead of
      // letting playback fail later with UnsupportedClassVersionError.
      String? javaVersion;
      String? javaWarning;
      final jar = config.environment['ABYSS_DL_JAR']?.trim();
      if (jar != null && jar.isNotEmpty && File(jar).existsSync()) {
        final javaMajor = config.javaMajorVersion;
        if (config.javaExecutable == null) {
          javaWarning = 'Java 21+ not found (abyss-dl.jar needs 21+)';
        } else if (javaMajor != null &&
            javaMajor < JavaRuntime.minimumMajorVersion) {
          javaWarning =
              'Java $javaMajor is too old for abyss-dl.jar (needs 21+)';
        } else {
          javaVersion = config.javaVersion ?? javaMajor?.toString();
        }
        if (javaWarning != null) {
          _logger.warning(
            'Configured Java runtime cannot run abyss-dl.jar',
            context: {
              'java': config.javaExecutable ?? 'not found',
              'javaMajor': config.javaMajorVersion ?? 'unknown',
              'required': JavaRuntime.minimumMajorVersion,
            },
          );
        }
      }

      return EngineHealth.ready(
        nodeVersion: version.isEmpty ? 'unknown' : version,
        enginePath: config.scriptPath,
        javaVersion: javaVersion,
        warning: javaWarning,
      );
    } on TimeoutException {
      return EngineHealth.unavailable(
        'Node.js did not respond to --version within 8 seconds.',
        enginePath: config.scriptPath,
      );
    } on ProcessException {
      return EngineHealth.unavailable(
        'Node.js executable "${config.nodeExecutable}" was not found. '
        'Install Node.js 18+ or set ANIME_TUI_NODE.',
        enginePath: config.scriptPath,
      );
    } on Object catch (error) {
      return EngineHealth.unavailable(
        'Engine health check failed: $error',
        enginePath: config.scriptPath,
      );
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final processes = List<Process>.of(_live.values);
    _live.clear();
    for (final process in processes) {
      try {
        process.kill(ProcessSignal.sigkill);
      } on Object {
        // ignore
      }
    }
  }
}
