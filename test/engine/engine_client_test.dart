import 'package:anime_tui_native/core/errors/engine_exception.dart';
import 'package:anime_tui_native/core/logging/app_logger.dart';
import 'package:anime_tui_native/engine/engine_client.dart';
import 'package:anime_tui_native/engine/engine_command.dart';
import 'package:anime_tui_native/engine/engine_config.dart';
import 'package:anime_tui_native/engine/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_transport.dart';

void main() {
  EngineConfig config({Duration? networkTimeout}) => EngineConfig(
        nodeExecutable: 'node',
        scriptPath: '/tmp/anime.js',
        workingDirectory: '/tmp',
        networkTimeout: networkTimeout ?? const Duration(seconds: 1),
      );

  EngineClient client(FakeTransport transport, {Duration? networkTimeout}) =>
      EngineClient(
        transport: transport,
        config: config(networkTimeout: networkTimeout),
        logger: AppLogger(maxEntries: 50),
      );

  group('command protocol', () {
    test('search uses an argv array, not a shell string', () async {
      final transport = FakeTransport(replies: <EngineCommandKind, FakeReply>{
        EngineCommandKind.search: const FakeReply(
          stdout: <String>['Naruto\thttps://example.com/naruto\tposter'],
        ),
      });

      final results =
          await client(transport).search('naruto shippuden; rm -rf /');

      expect(results.single.title, 'Naruto');
      expect(
        transport.commands.single.arguments,
        <String>['search', 'naruto shippuden; rm -rf /'],
      );
    });

    test('episodes-progress includes the preferred episode when supplied',
        () async {
      final transport = FakeTransport(replies: <EngineCommandKind, FakeReply>{
        EngineCommandKind.episodesProgress: const FakeReply(
          stdout: <String>[
            'Tập 1 · Resume 01:00\thttps://example.com/tap-1.html\tTập 1\t1',
            'Tập 2\thttps://example.com/tap-2.html\tTập 2\t0',
          ],
        ),
      });

      final episodes = await client(transport).episodes(
        'https://example.com/naruto',
        preferredEpisodeUrl: 'https://example.com/tap-2.html',
      );

      expect(episodes, hasLength(2));
      expect(episodes.first.preferred, isTrue);
      expect(
        transport.commands.single.arguments,
        <String>[
          'episodes-progress',
          'https://example.com/naruto',
          'https://example.com/tap-2.html',
        ],
      );
    });

    test('history completed passes the completed flag', () async {
      final transport = FakeTransport(replies: <EngineCommandKind, FakeReply>{
        EngineCommandKind.history: const FakeReply(
          stdout: <String>['Naruto [Tập 12]\thttps://example.com/naruto\t'],
        ),
      });

      final entries = await client(transport).history(completed: true);

      expect(entries.single.title, 'Naruto');
      expect(transport.commands.single.arguments,
          <String>['history', 'completed']);
    });

    test('history-add keeps spaces in a single argument', () async {
      final transport = FakeTransport();
      await client(transport).addHistory(
        title: 'One Piece',
        url: 'https://example.com/one-piece',
        poster: 'https://img.example/p.jpg',
        latestEpisode: 'Tập 100',
      );

      expect(transport.commands.single.arguments, <String>[
        'history-add',
        'One Piece',
        'https://example.com/one-piece',
        'https://img.example/p.jpg',
        'Tập 100',
      ]);
    });

    test('accepts root-relative history URLs from older engine files',
        () async {
      final transport = FakeTransport();

      await client(transport).setCompleted(
          '/phim/kimi-ga-shinu-made-koi-wo-shitai/',
          completed: true);

      expect(
        transport.commands.single.arguments,
        <String>['history-complete', '/phim/kimi-ga-shinu-made-koi-wo-shitai/'],
      );
    });

    test('rejects a bare relative path that the engine cannot resolve', () {
      expect(
        () => EngineCommand.setCompleted('phim/naruto', completed: true),
        throwsArgumentError,
      );
    });
  });

  group('stream resolution', () {
    test('returns the URL printed by the engine', () async {
      final transport = FakeTransport(replies: <EngineCommandKind, FakeReply>{
        EngineCommandKind.streams: const FakeReply(
          stdout: <String>['https://cdn.example.com/a.mp4?token=1'],
        ),
      });

      final url = await client(transport)
          .resolveStream('https://example.com/tap-1.html');
      expect(url, 'https://cdn.example.com/a.mp4?token=1');
    });
  });

  group('errors', () {
    test('non-zero exit becomes an EngineException with stderr details',
        () async {
      final transport = FakeTransport(replies: <EngineCommandKind, FakeReply>{
        EngineCommandKind.search: const FakeReply(
          stderr: <String>['network unreachable', 'retry later'],
          exitCode: 1,
        ),
      });

      await expectLater(
        client(transport).search('naruto'),
        throwsA(isA<EngineException>()
            .having((e) => e.kind, 'kind', EngineErrorKind.exitFailure)
            .having((e) => e.exitCode, 'exitCode', 1)
            .having(
                (e) => e.details, 'details', contains('network unreachable'))),
      );
    });

    test('hanging commands time out and are stopped', () async {
      final transport = FakeTransport(replies: <EngineCommandKind, FakeReply>{
        EngineCommandKind.search: const FakeReply(hang: true),
      });
      final engine = client(
        transport,
        networkTimeout: const Duration(milliseconds: 80),
      );

      await expectLater(
        engine.search('slow'),
        throwsA(isA<EngineException>().having(
          (e) => e.kind,
          'kind',
          EngineErrorKind.timeout,
        )),
      );
    }, timeout: const Timeout(Duration(seconds: 5)));
  });

  group('playback', () {
    test('builds the four positional arguments and streams status', () async {
      final transport = FakeTransport(replies: <EngineCommandKind, FakeReply>{
        EngineCommandKind.playEpisode: const FakeReply(
          stdout: <String>['finished'],
          stderr: <String>[
            'Preparing Naruto 10% · Resume at 01:00',
            'Playing Naruto 50% · 10:00 / 20:00',
          ],
        ),
      });
      final engine = client(transport);
      final session = await engine.play(const PlaybackRequest(
        streamUrl: 'https://cdn.example.com/a.mp4',
        animeUrl: 'https://example.com/naruto',
        episodeUrl: 'https://example.com/tap-1.html',
        label: 'Naruto — Tập 1',
      ));

      final statuses = <PlaybackStatus>[];
      final subscription = session.statuses.listen(statuses.add);
      final result = await session.result;
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(result.outcome, PlaybackOutcome.finished);
      expect(statuses, hasLength(2));
      expect(statuses.last.stage, PlaybackStage.playing);
      expect(
          transport.commands.single.arguments,
          containsAllInOrder(<String>[
            'play-episode',
            'https://cdn.example.com/a.mp4',
            'https://example.com/naruto',
            'https://example.com/tap-1.html',
            'Naruto — Tập 1',
          ]));
      expect(transport.commands.single.arguments, contains('--progressive'));
      expect(transport.commands.single.arguments, contains('1'));
    });

    test('failed playback carries stderr as the error', () async {
      final transport = FakeTransport(replies: <EngineCommandKind, FakeReply>{
        EngineCommandKind.playEpisode: const FakeReply(
          stdout: <String>['failed'],
          stderr: <String>['mpv: could not open stream'],
          exitCode: 1,
        ),
      });

      final session = await client(transport).play(const PlaybackRequest(
        streamUrl: 'https://cdn.example.com/a.mp4',
        animeUrl: 'https://example.com/naruto',
        episodeUrl: 'https://example.com/tap-1.html',
        label: 'Naruto — Tập 1',
      ));
      final result = await session.result;

      expect(result.outcome, PlaybackOutcome.failed);
      expect(result.error, contains('could not open stream'));
    });

    test('stopping a hung playback reports stopped, not a protocol error',
        () async {
      final transport = FakeTransport(replies: <EngineCommandKind, FakeReply>{
        EngineCommandKind.playEpisode: const FakeReply(hang: true),
      });

      final session = await client(transport).play(const PlaybackRequest(
        streamUrl: 'https://cdn.example.com/a.mp4',
        animeUrl: 'https://example.com/naruto',
        episodeUrl: 'https://example.com/tap-1.html',
        label: 'Naruto — Tập 1',
      ));
      await session.stop();
      final result = await session.result;

      expect(result.outcome, PlaybackOutcome.stopped);
    });
  });
}
