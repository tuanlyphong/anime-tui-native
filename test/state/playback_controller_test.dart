import 'dart:async';

import 'package:anime_tui_native/core/errors/engine_exception.dart';
import 'package:anime_tui_native/core/logging/app_logger.dart';
import 'package:anime_tui_native/engine/engine_client.dart';
import 'package:anime_tui_native/engine/models.dart';
import 'package:anime_tui_native/state/playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_engine.dart';

void main() {
  late FakeEngine engine;
  late PlaybackController controller;

  const anime = AnimeSummary(
    title: 'Naruto',
    url: 'https://example.com/phim/naruto',
  );
  const episode = Episode(
    title: 'Tập 1',
    url: 'https://example.com/phim/naruto/tap-1.html',
  );

  setUp(() {
    engine = FakeEngine();
    controller = PlaybackController(
      engine: engine,
      logger: AppLogger(maxEntries: 50),
    );
  });

  tearDown(() {
    controller.dispose();
  });

  test('play resolves the stream, starts the engine and records history',
      () async {
    await controller.play(anime: anime, episode: episode);

    expect(engine.playRequests, hasLength(1));
    final request = engine.playRequests.single;
    expect(request.streamUrl, engine.streamUrl);
    expect(request.animeUrl, anime.url);
    expect(request.episodeUrl, episode.url);
    expect(request.label, 'Naruto — Tập 1');
    expect(engine.historyAdds.single['title'], 'Naruto');

    expect(controller.phase, PlaybackPhase.finished);
    expect(controller.statusText, 'Finished');
    expect(controller.error, isNull);
  });

  test('stream resolution failure becomes a visible error', () async {
    engine.streamError = EngineException(
      EngineErrorKind.exitFailure,
      'stream lookup failed',
      exitCode: 1,
    );

    await controller.play(anime: anime, episode: episode);

    expect(controller.phase, PlaybackPhase.failed);
    expect(controller.error, isNotNull);
    expect(engine.playRequests, isEmpty);
  });

  test('stop ends an active playback as stopped', () async {
    engine.playbackGate = Completer<void>();

    final playback = controller.play(anime: anime, episode: episode);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.isBusy, isTrue);

    await controller.stop();
    await playback;

    expect(controller.phase, PlaybackPhase.stopped);
    expect(controller.statusText, 'Stopped');
    engine.playbackGate!.complete();
  });

  test('stop during stream resolution cancels the pending playback', () async {
    engine.streamGate = Completer<void>();

    final playback = controller.play(anime: anime, episode: episode);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.phase, PlaybackPhase.resolving);

    await controller.stop();
    expect(controller.phase, PlaybackPhase.stopped);

    engine.streamGate!.complete();
    await playback;

    expect(controller.phase, PlaybackPhase.stopped);
    expect(controller.statusText, 'Stopped');
    expect(engine.playRequests, isEmpty);
  });

  test('failed playback surfaces the engine error', () async {
    engine.playbackResult = const PlaybackResult(
      outcome: PlaybackOutcome.failed,
      error: 'mpv: could not open stream',
    );

    await controller.play(anime: anime, episode: episode);

    expect(controller.phase, PlaybackPhase.failed);
    expect(controller.error, contains('could not open stream'));
  });

  group('playback session factory', () {
    test('uses the injected session instead of the engine player', () async {
      final requests = <PlaybackRequest>[];
      final statuses = StreamController<PlaybackStatus>();
      final result = Completer<PlaybackResult>();
      var stopped = 0;

      controller.dispose();
      controller = PlaybackController(
        engine: engine,
        logger: AppLogger(maxEntries: 50),
        sessionFactory: (request) async {
          requests.add(request);
          scheduleMicrotask(() {
            statuses.add(const PlaybackStatus(
              stage: PlaybackStage.playing,
              text: 'Playing in WebView',
              percent: 0.5,
            ));
            result.complete(
              const PlaybackResult(outcome: PlaybackOutcome.finished),
            );
            statuses.close();
          });
          return PlaybackSession(
            statuses: statuses.stream,
            result: result.future,
            stop: () async {
              stopped++;
            },
          );
        },
      );

      await controller.play(anime: anime, episode: episode);

      expect(engine.playRequests, isEmpty);
      expect(requests, hasLength(1));
      expect(requests.single.streamUrl, engine.streamUrl);
      expect(requests.single.animeUrl, anime.url);
      expect(requests.single.episodeUrl, episode.url);
      expect(requests.single.label, 'Naruto — Tập 1');
      expect(controller.phase, PlaybackPhase.finished);
      expect(stopped, 0);
    });

    test('stop closes the injected session', () async {
      final statuses = StreamController<PlaybackStatus>();
      final result = Completer<PlaybackResult>();
      var stopped = 0;

      controller.dispose();
      controller = PlaybackController(
        engine: engine,
        logger: AppLogger(maxEntries: 50),
        sessionFactory: (request) async => PlaybackSession(
          statuses: statuses.stream,
          result: result.future,
          stop: () async {
            stopped++;
            if (!result.isCompleted) {
              result.complete(
                const PlaybackResult(outcome: PlaybackOutcome.stopped),
              );
            }
            await statuses.close();
          },
        ),
      );

      final playback = controller.play(anime: anime, episode: episode);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.isBusy, isTrue);

      await controller.stop();
      await playback;

      expect(stopped, 1);
      expect(controller.phase, PlaybackPhase.stopped);
    });

    test('a failed injected session surfaces its error', () async {
      controller.dispose();
      controller = PlaybackController(
        engine: engine,
        logger: AppLogger(maxEntries: 50),
        sessionFactory: (request) async {
          final statuses = StreamController<PlaybackStatus>();
          unawaited(statuses.close());
          return PlaybackSession(
            statuses: statuses.stream,
            result: Future<PlaybackResult>.value(
              const PlaybackResult(
                outcome: PlaybackOutcome.failed,
                error: 'WebView could not load the player',
              ),
            ),
            stop: () async {},
          );
        },
      );

      await controller.play(anime: anime, episode: episode);

      expect(controller.phase, PlaybackPhase.failed);
      expect(controller.error, contains('WebView could not load'));
    });
  });
}
