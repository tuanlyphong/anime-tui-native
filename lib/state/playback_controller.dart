import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/errors/engine_exception.dart';
import '../core/logging/app_logger.dart';
import '../engine/engine_client.dart';
import '../engine/models.dart';

enum PlaybackPhase {
  idle,
  resolving,
  starting,
  playing,
  stopping,
  finished,
  stopped,
  failed,
}

/// Drives stream resolution, engine playback, and the persistent now-playing
/// bar. mpv owns the actual video window; this controller tracks the engine
/// process and its status output.
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required AnimeEngine engine,
    required AppLogger logger,
  })  : _engine = engine,
        _logger = logger;

  AnimeEngine _engine;
  final AppLogger _logger;

  PlaybackPhase _phase = PlaybackPhase.idle;
  AnimeSummary? _anime;
  Episode? _episode;
  String _statusText = '';
  double? _progress;
  String? _error;
  PlaybackSession? _session;
  StreamSubscription<PlaybackStatus>? _statusSubscription;
  int _generation = 0;
  bool _disposed = false;

  PlaybackPhase get phase => _phase;
  AnimeSummary? get anime => _anime;
  Episode? get episode => _episode;
  String get statusText => _statusText;
  double? get progress => _progress;
  String? get error => _error;

  bool get isBusy =>
      _phase == PlaybackPhase.resolving ||
      _phase == PlaybackPhase.starting ||
      _phase == PlaybackPhase.playing ||
      _phase == PlaybackPhase.stopping;

  bool get isActive => _anime != null && _phase != PlaybackPhase.idle;

  String get label {
    final animeTitle = _anime?.title ?? '';
    final episodeTitle = _cleanEpisodeTitle(_episode);
    if (animeTitle.isEmpty) return episodeTitle;
    if (episodeTitle.isEmpty) return animeTitle;
    return '$animeTitle · $episodeTitle';
  }

  void updateEngine(AnimeEngine engine) {
    _engine = engine;
    unawaited(_closeSession());
    _generation++;
    _reset();
    _notify();
  }

  Future<void> play({
    required AnimeSummary anime,
    required Episode episode,
  }) async {
    if (episode.url.isEmpty) return;

    // Selecting another episode while one is active: stop the old one first.
    if (isBusy) {
      await stop();
    }

    final generation = ++_generation;
    _anime = anime;
    _episode = episode;
    _phase = PlaybackPhase.resolving;
    _statusText = 'Resolving stream…';
    _progress = null;
    _error = null;
    _notify();

    try {
      final streamUrl = await _engine.resolveStream(episode.url);
      if (generation != _generation || _disposed) return;

      _phase = PlaybackPhase.starting;
      _statusText = 'Starting player…';
      _notify();

      final session = await _engine.play(PlaybackRequest(
        streamUrl: streamUrl,
        animeUrl: anime.url,
        episodeUrl: episode.url,
        label: _playbackLabel(anime, episode),
      ));
      if (generation != _generation || _disposed) {
        await session.stop();
        return;
      }
      _session = session;
      unawaited(_recordHistory(anime, episode));

      _statusSubscription?.cancel();
      _statusSubscription = session.statuses.listen((status) {
        if (generation != _generation || _disposed) return;
        // A late status event must not overwrite a terminal state.
        if (_phase == PlaybackPhase.finished ||
            _phase == PlaybackPhase.stopped ||
            _phase == PlaybackPhase.failed ||
            _phase == PlaybackPhase.idle) {
          return;
        }
        _phase = status.stage == PlaybackStage.preparing
            ? PlaybackPhase.starting
            : PlaybackPhase.playing;
        _statusText = status.text;
        _progress = status.percent;
        _notify();
      }, onError: (Object error) {
        _logger.warning('Playback status stream failed', error: error);
      });

      _phase = PlaybackPhase.playing;
      _statusText = 'Playing…';
      _notify();

      final result = await session.result;
      if (generation != _generation || _disposed) return;

      _progress = result.outcome == PlaybackOutcome.finished ? 1 : _progress;
      _phase = switch (result.outcome) {
        PlaybackOutcome.finished => PlaybackPhase.finished,
        PlaybackOutcome.stopped => PlaybackPhase.stopped,
        PlaybackOutcome.failed => PlaybackPhase.failed,
      };
      _statusText = switch (result.outcome) {
        PlaybackOutcome.finished => 'Finished',
        PlaybackOutcome.stopped => 'Stopped',
        PlaybackOutcome.failed => 'Playback failed',
      };
      if (result.outcome == PlaybackOutcome.failed) {
        _error = result.error?.trim().isNotEmpty == true
            ? result.error!.trim().split('\n').last
            : 'The player exited unexpectedly. See the Logs tab.';
      }
      await _statusSubscription?.cancel();
      _statusSubscription = null;
      _session = null;
      _notify();
    } on Object catch (error, stackTrace) {
      if (generation != _generation || _disposed) return;
      final failure = EngineException.from(error, stackTrace: stackTrace);
      _phase = PlaybackPhase.failed;
      _statusText = 'Playback failed';
      _error = failure.userMessage;
      _session = null;
      _logger.error(
        'Could not start playback',
        error: error,
        stackTrace: stackTrace,
        context: {'anime': anime.title, 'episode': episode.title},
      );
      _notify();
    }
  }

  Future<void> stop() async {
    // Cancellation during stream resolution or process startup: bump the
    // generation so the in-flight request is discarded when it returns.
    if (_session == null &&
        (_phase == PlaybackPhase.resolving ||
            _phase == PlaybackPhase.starting)) {
      _generation++;
      _phase = PlaybackPhase.stopped;
      _statusText = 'Stopped';
      _progress = null;
      _notify();
      return;
    }

    final session = _session;
    if (session == null) return;
    _phase = PlaybackPhase.stopping;
    _statusText = 'Stopping player…';
    _notify();
    try {
      await session.stop();
    } on Object catch (error) {
      _logger.warning('Could not stop playback cleanly', error: error);
    }
  }

  void dismiss() {
    if (isBusy) return;
    _generation++;
    unawaited(_closeSession());
    _reset();
    _notify();
  }

  Future<void> _recordHistory(AnimeSummary anime, Episode episode) async {
    try {
      await _engine.addHistory(
        title: anime.title,
        url: anime.url,
        poster: anime.poster,
        latestEpisode: _cleanEpisodeTitle(episode),
      );
    } on Object catch (error, stackTrace) {
      // History is a nice-to-have; never block playback on it.
      _logger.warning(
        'Could not update history before playback',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  String _playbackLabel(AnimeSummary anime, Episode episode) {
    final title = anime.title.trim();
    final ep = _cleanEpisodeTitle(episode).trim();
    if (title.isEmpty) return ep;
    if (ep.isEmpty) return title;
    return '$title — $ep';
  }

  String _cleanEpisodeTitle(Episode? episode) {
    if (episode == null) return '';
    return episode.originalTitle.trim().isNotEmpty
        ? episode.originalTitle.trim()
        : episode.title.trim();
  }

  Future<void> _closeSession() async {
    await _statusSubscription?.cancel();
    _statusSubscription = null;
    final session = _session;
    _session = null;
    if (session != null) {
      try {
        await session.stop();
      } on Object {
        // ignore
      }
    }
  }

  void _reset() {
    _phase = PlaybackPhase.idle;
    _anime = null;
    _episode = null;
    _statusText = '';
    _progress = null;
    _error = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_closeSession());
    super.dispose();
  }
}
