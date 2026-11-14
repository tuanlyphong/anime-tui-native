import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../app/app_settings.dart';
import '../core/errors/engine_exception.dart';
import '../core/logging/app_logger.dart';
import '../core/utils/async_semaphore.dart';
import 'engine_command.dart';
import 'engine_config.dart';
import 'engine_transport.dart';
import 'java_runtime.dart';
import 'models.dart';
import 'parsers.dart';

/// One active playback process.
class PlaybackSession {
  PlaybackSession({
    required this.statuses,
    required this.result,
    required this.stop,
  });

  /// Live status lines from the engine's stderr (non-TTY mode).
  final Stream<PlaybackStatus> statuses;

  /// Completes when mpv closes, the user stops, or the engine fails.
  final Future<PlaybackResult> result;

  final Future<void> Function() stop;
}

/// High-level, typed engine API used by controllers.
abstract interface class AnimeEngine {
  Future<List<AnimeSummary>> search(String query);

  Future<List<Episode>> episodes(
    String animeUrl, {
    String? preferredEpisodeUrl,
  });

  Future<String> resolveStream(String episodeUrl);

  Future<PlaybackSession> play(PlaybackRequest request);

  Future<List<HistoryEntry>> history({required bool completed});

  Future<void> addHistory({
    required String title,
    required String url,
    required String poster,
    required String latestEpisode,
  });

  Future<void> setCompleted(String url, {required bool completed});

  /// Merge [entries] into the engine's on-disk history. Imported entries take
  /// precedence over local ones with the same URL.
  Future<void> importHistory(List<HistoryEntry> entries);

  Future<EngineHealth> checkHealth();

  Future<void> dispose();
}

class EngineClient implements AnimeEngine {
  EngineClient({
    required this.transport,
    required this.config,
    AppLogger? logger,
  }) : _logger = logger ?? AppLogger.instance;

  final EngineTransport transport;
  final EngineConfig config;
  final AppLogger _logger;

  final AsyncSemaphore _semaphore = AsyncSemaphore(2);

  @override
  Future<List<AnimeSummary>> search(String query) async {
    final lines = await _run(
      EngineCommand.search(query, timeout: config.networkTimeout),
    );
    final results = parseSearchResults(lines);
    _logger.info(
      'Search completed',
      context: {'query': query, 'results': results.length},
    );
    return results;
  }

  @override
  Future<List<Episode>> episodes(
    String animeUrl, {
    String? preferredEpisodeUrl,
  }) async {
    final lines = await _run(
      EngineCommand.episodes(
        animeUrl,
        preferredEpisodeUrl: preferredEpisodeUrl,
        timeout: config.networkTimeout,
      ),
    );
    final episodes = parseEpisodes(lines);
    _logger.info(
      'Episodes loaded',
      context: {'url': animeUrl, 'episodes': episodes.length},
    );
    return episodes;
  }

  @override
  Future<String> resolveStream(String episodeUrl) async {
    final lines = await _run(
      EngineCommand.streams(episodeUrl, timeout: config.networkTimeout),
    );
    final url = parseStreamUrl(lines);
    _logger.info(
      'Stream resolved',
      context: {'episode': episodeUrl, 'host': Uri.parse(url).host},
    );
    return url;
  }

  @override
  Future<PlaybackSession> play(PlaybackRequest request) async {
    var jar = (config.environment['ABYSS_DL_JAR'] ?? '').trim();
    if (jar.isEmpty) {
      jar = AppSettings.discoverAbyssJarPath();
    }
    // The `streams` command only yields Abyss page URLs, which mpv cannot
    // play directly. Without the abyss-dl.jar downloader the engine falls
    // back to direct mpv on an HTML page and ends almost immediately as
    // "stopped". Fail fast with an actionable error instead of silently
    // spawning a doomed playback process.
    final isAbyss =
        RegExp(r'abyssplayer\.com/([^/?#]+)').hasMatch(request.streamUrl);
    if (isAbyss) {
      if (jar.isEmpty) {
        throw EngineException(
          EngineErrorKind.notConfigured,
          'Abyss streams need the abyss-dl.jar downloader, but none is '
          'configured. Set the abyss-dl.jar path in Settings or set the '
          'ABYSS_DL_JAR environment variable.',
          command: 'play',
        );
      }
      if (!File(jar).existsSync()) {
        throw EngineException(
          EngineErrorKind.notConfigured,
          'The abyss-dl.jar downloader was not found at $jar.',
          details: 'Set the abyss-dl.jar path in Settings or the '
              'ABYSS_DL_JAR environment variable.',
          command: 'play',
        );
      }

      // abyss-dl.jar is compiled for Java 21 (class file 65). Validate the
      // runtime here so the user sees an actionable message instead of
      // `UnsupportedClassVersionError` buried in the engine's stderr.
      final java =
          config.javaMajorVersion != null && config.javaExecutable != null
              ? JavaRuntime(
                  home: config.javaHome ?? '',
                  executable: config.javaExecutable!,
                  version: config.javaVersion ?? '${config.javaMajorVersion}',
                  majorVersion: config.javaMajorVersion!,
                )
              : JavaRuntime.discover();
      if (java == null) {
        throw EngineException(
          EngineErrorKind.notConfigured,
          'abyss-dl.jar requires Java 21+, but no compatible Java runtime was '
          'found. Install Java 21 or point JAVA_HOME / ANIME_TUI_JAVA_HOME at '
          'a Java 21+ JDK.',
          command: 'play',
        );
      }
      if (java.majorVersion < JavaRuntime.minimumMajorVersion) {
        throw EngineException(
          EngineErrorKind.notConfigured,
          'abyss-dl.jar requires Java 21+, but the selected runtime is Java '
          '${java.majorVersion} (${java.executable}). Point JAVA_HOME or '
          'ANIME_TUI_JAVA_HOME at a Java 21+ JDK.',
          details: 'Detected Java ${java.version} at ${java.executable}.',
          command: 'play',
        );
      }
    }

    final command = EngineCommand.playEpisode(
      request,
      player: config.environment['PLAYER'] ?? 'mpv',
      progressive: config.environment['ABYSS_PROGRESSIVE'] != '0',
      quality: config.environment['ABYSS_QUALITY'] ?? 'h',
      jar: jar,
    );

    final run = await transport.start(command);
    final statusController = StreamController<PlaybackStatus>();
    final stdoutLines = <String>[];
    final stderrLines = <String>[];

    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();

    final stdoutSub = run.stdout.listen(
      stdoutLines.add,
      onError: (Object error, StackTrace stackTrace) {
        _logger.warning('Playback stdout error',
            error: error, stackTrace: stackTrace);
        if (!stdoutDone.isCompleted) stdoutDone.complete();
      },
      onDone: () {
        if (!stdoutDone.isCompleted) stdoutDone.complete();
      },
    );

    final stderrSub = run.stderr.listen(
      (line) {
        stderrLines.add(line);
        final status = parsePlaybackStatus(line);
        if (status != null && !statusController.isClosed) {
          statusController.add(status);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _logger.warning('Playback stderr error',
            error: error, stackTrace: stackTrace);
        if (!stderrDone.isCompleted) stderrDone.complete();
      },
      onDone: () {
        if (!stderrDone.isCompleted) stderrDone.complete();
      },
    );

    var stopRequested = false;

    final result = () async {
      final code = await run.exitCode;
      await _drain(<Completer<void>>[stdoutDone, stderrDone]);
      await stdoutSub.cancel();
      await stderrSub.cancel();

      // anime.js prints the outcome (`finished`/`stopped`/`failed`) on
      // stdout; stderr carries the live status lines. Prefer stdout, then fall
      // back to stderr for older engine builds, and finally treat a killed
      // process as an intentional stop rather than a protocol error.
      PlaybackOutcome outcome;
      try {
        outcome = parsePlaybackOutcome(stdoutLines);
      } on EngineException {
        try {
          outcome = parsePlaybackOutcome(stderrLines);
        } on EngineException {
          outcome =
              stopRequested ? PlaybackOutcome.stopped : PlaybackOutcome.failed;
        }
      }

      if (code != 0 && outcome == PlaybackOutcome.finished) {
        outcome = PlaybackOutcome.failed;
      }

      final errorText = stderrLines.isEmpty ? null : stderrLines.join('\n');
      if (outcome == PlaybackOutcome.failed) {
        _logger.error(
          'Playback failed',
          context: {
            'exit': code,
            'command': command.label,
            if (errorText != null && errorText.isNotEmpty)
              'stderr': errorText.replaceAll('\n', ' | '),
          },
        );
      } else {
        _logger.info(
          'Playback ended',
          context: {
            'outcome': outcome.name,
            'exit': code,
            'ms': run.elapsed.inMilliseconds,
          },
        );
      }

      if (!statusController.isClosed) {
        // Do not await: a single-subscription controller with no listener
        // never completes its close() future, which would hang playback.
        unawaited(statusController.close());
      }
      return PlaybackResult(
        outcome: outcome,
        error: outcome == PlaybackOutcome.failed ? errorText : null,
        statusLines: List<String>.unmodifiable(stderrLines),
      );
    }();

    return PlaybackSession(
      statuses: statusController.stream,
      result: result,
      stop: () async {
        stopRequested = true;
        await run.stop();
      },
    );
  }

  Future<void> _drain(List<Completer<void>> completers) async {
    try {
      await Future.wait(
        completers.map((completer) => completer.future),
      ).timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _logger.warning('Timed out waiting for engine output to drain');
    }
  }

  @override
  Future<List<HistoryEntry>> history({required bool completed}) async {
    final lines = await _run(EngineCommand.history(completed: completed));
    final entries = parseHistory(lines, completed: completed);
    _logger.info(
      'History loaded',
      context: {'completed': completed, 'entries': entries.length},
    );
    return entries;
  }

  @override
  Future<void> addHistory({
    required String title,
    required String url,
    required String poster,
    required String latestEpisode,
  }) async {
    await _run(EngineCommand.historyAdd(
      title: title,
      url: url,
      poster: poster,
      latestEpisode: latestEpisode,
    ));
  }

  @override
  Future<void> setCompleted(String url, {required bool completed}) async {
    await _run(EngineCommand.setCompleted(url, completed: completed));
  }

  @override
  Future<void> importHistory(List<HistoryEntry> entries) async {
    if (entries.isEmpty) return;
    final directory =
        await Directory.systemTemp.createTemp('anime-tui-history-');
    final file = File(
      '${directory.path}${Platform.pathSeparator}history-import.json',
    );
    try {
      await file.writeAsString(
        jsonEncode(entries.map((entry) => entry.toJson()).toList()),
        flush: true,
      );
      await _run(EngineCommand.importHistory(file.path));
      _logger.info(
        'History import merged',
        context: {'entries': entries.length},
      );
    } finally {
      try {
        await directory.delete(recursive: true);
      } on Object {
        // Temp cleanup is best effort.
      }
    }
  }

  @override
  Future<EngineHealth> checkHealth() => transport.healthCheck();

  Future<List<String>> _run(EngineCommand command) {
    return _semaphore.run<List<String>>(() async {
      final stopwatch = Stopwatch()..start();
      final run = await transport.start(command);
      final stdoutLines = <String>[];
      final stderrLines = <String>[];

      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();

      final stdoutSub = run.stdout.listen(
        stdoutLines.add,
        onError: (Object error, StackTrace stackTrace) {
          _logger.warning('Engine stdout error',
              error: error, stackTrace: stackTrace);
          if (!stdoutDone.isCompleted) stdoutDone.complete();
        },
        onDone: () {
          if (!stdoutDone.isCompleted) stdoutDone.complete();
        },
      );
      final stderrSub = run.stderr.listen(
        stderrLines.add,
        onError: (Object error, StackTrace stackTrace) {
          _logger.warning('Engine stderr error',
              error: error, stackTrace: stackTrace);
          if (!stderrDone.isCompleted) stderrDone.complete();
        },
        onDone: () {
          if (!stderrDone.isCompleted) stderrDone.complete();
        },
      );

      int exitCode;
      try {
        exitCode = await _awaitExit(run, command.timeout);
      } on TimeoutException {
        await run.stop();
        await stdoutSub.cancel();
        await stderrSub.cancel();
        throw EngineException(
          EngineErrorKind.timeout,
          '${command.label} timed out after '
          '${command.timeout!.inSeconds}s.',
          details: stderrLines.join('\n'),
          command: command.label,
        );
      }

      await _drain(<Completer<void>>[stdoutDone, stderrDone]);
      await stdoutSub.cancel();
      await stderrSub.cancel();

      _logger.debug(
        'Engine command finished',
        context: {
          'command': command.label,
          'exit': exitCode,
          'ms': stopwatch.elapsedMilliseconds,
          'stdoutLines': stdoutLines.length,
          'stderrLines': stderrLines.length,
        },
      );

      if (exitCode != 0) {
        final details =
            stderrLines.where((line) => line.trim().isNotEmpty).join('\n');
        throw EngineException(
          EngineErrorKind.exitFailure,
          details.isEmpty
              ? '${command.label} failed with exit code $exitCode.'
              : details.split('\n').last,
          details: details.isEmpty ? null : details,
          exitCode: exitCode,
          command: command.label,
        );
      }

      return stdoutLines;
    });
  }

  Future<int> _awaitExit(EngineRun run, Duration? timeout) {
    if (timeout == null) return run.exitCode;
    return run.exitCode.timeout(timeout);
  }

  @override
  Future<void> dispose() => transport.dispose();
}
