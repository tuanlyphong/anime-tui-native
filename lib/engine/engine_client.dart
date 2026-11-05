import 'dart:async';

import '../core/errors/engine_exception.dart';
import '../core/logging/app_logger.dart';
import '../core/utils/async_semaphore.dart';
import 'engine_command.dart';
import 'engine_config.dart';
import 'engine_transport.dart';
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
    final command = EngineCommand.playEpisode(
      request,
      player: config.environment['PLAYER'] ?? 'mpv',
      progressive: config.environment['ABYSS_PROGRESSIVE'] != '0',
      quality: config.environment['ABYSS_QUALITY'] ?? 'h',
      jar: config.environment['ABYSS_DL_JAR'] ?? '',
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

      PlaybackOutcome outcome;
      try {
        outcome = parsePlaybackOutcome(stdoutLines);
      } on EngineException {
        // A killed process often has no stdout. Treat that as an intentional
        // stop rather than a confusing protocol error.
        outcome =
            stopRequested ? PlaybackOutcome.stopped : PlaybackOutcome.failed;
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
