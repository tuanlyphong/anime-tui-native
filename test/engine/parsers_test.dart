import 'package:anime_tui_native/core/errors/engine_exception.dart';
import 'package:anime_tui_native/engine/models.dart';
import 'package:anime_tui_native/engine/parsers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitizeLine', () {
    test('removes ANSI sequences, carriage returns and control characters', () {
      const raw = '\r\x1B[2KPlaying Naruto 25% · 05:00 / 20:00';
      expect(sanitizeLine(raw), 'Playing Naruto 25% · 05:00 / 20:00');
    });
  });

  group('parseSearchResults', () {
    test('parses title, url and poster', () {
      final results = parseSearchResults(<String>[
        'Naruto\thttps://example.com/naruto\thttps://img.example/n.jpg',
        'One Piece\thttps://example.com/one-piece\t',
      ]);

      expect(results, hasLength(2));
      expect(results.first.title, 'Naruto');
      expect(results.first.poster, 'https://img.example/n.jpg');
      expect(results.last.poster, isEmpty);
    });

    test('skips malformed rows instead of failing the whole search', () {
      final results = parseSearchResults(<String>[
        'No URL row',
        '\thttps://example.com/valid\tposter',
        '',
      ]);

      expect(results, hasLength(1));
      expect(results.single.url, 'https://example.com/valid');
      expect(results.single.title, 'https://example.com/valid');
    });
  });

  group('parseEpisodes', () {
    test('parses display title, url, original title and preferred flag', () {
      final episodes = parseEpisodes(<String>[
        'Tập 1 · Resume 04:12\thttps://example.com/tap-1.html\tTập 1\t1',
        'Tập 2\thttps://example.com/tap-2.html\tTập 2\t0',
      ]);

      expect(episodes, hasLength(2));
      expect(episodes.first.title, contains('Resume'));
      expect(episodes.first.originalTitle, 'Tập 1');
      expect(episodes.first.preferred, isTrue);
      expect(episodes.first.badge, '01');
      expect(episodes.last.preferred, isFalse);
      expect(episodes.last.hasProgress, isFalse);
    });
  });

  group('parseHistory', () {
    test('splits the latest episode suffix from the title', () {
      final entries = parseHistory(
        <String>['Naruto [Tập 12]\thttps://example.com/naruto\tposter'],
        completed: false,
      );

      expect(entries.single.title, 'Naruto');
      expect(entries.single.latestEpisode, 'Tập 12');
      expect(entries.single.completed, isFalse);
    });
  });

  group('parseStreamUrl', () {
    test('returns the last non-empty URL', () {
      expect(
        parseStreamUrl(<String>['https://cdn.example.com/a.mp4?token=1']),
        'https://cdn.example.com/a.mp4?token=1',
      );
    });

    test('rejects an empty response', () {
      expect(
        () => parseStreamUrl(const <String>[]),
        throwsA(isA<EngineException>().having(
          (error) => error.kind,
          'kind',
          EngineErrorKind.protocol,
        )),
      );
    });

    test('rejects non-http protocols', () {
      expect(
        () => parseStreamUrl(<String>['file:///etc/passwd']),
        throwsA(isA<EngineException>()),
      );
    });
  });

  group('parsePlaybackStatus', () {
    test('parses preparing and playing status lines', () {
      final preparing = parsePlaybackStatus(
        '\r\x1B[2KPreparing Naruto 12% · Resume at 02:00 · Buffered to 03:00',
      );
      expect(preparing, isNotNull);
      expect(preparing!.stage, PlaybackStage.preparing);
      expect(preparing.percent, closeTo(0.12, 0.001));

      final playing = parsePlaybackStatus(
        'Playing Naruto 40% · 08:00 / 20:00',
      );
      expect(playing, isNotNull);
      expect(playing!.stage, PlaybackStage.playing);
      expect(playing.percent, closeTo(0.4, 0.001));
    });

    test('parses the real engine "<label> playing …" format', () {
      final playing = parsePlaybackStatus(
        'Boruto: Naruto Những Thế Hệ Kế Tiếp — Tập 001 playing 50% · 10:00 / 20:00',
      );
      expect(playing, isNotNull);
      expect(playing!.stage, PlaybackStage.playing);
      expect(playing.percent, closeTo(0.5, 0.001));
    });

    test('returns null for unrelated stderr', () {
      expect(parsePlaybackStatus('mpv: some diagnostic'), isNull);
    });
  });

  group('parsePlaybackOutcome', () {
    test('parses the three documented outcomes', () {
      expect(
          parsePlaybackOutcome(<String>['finished']), PlaybackOutcome.finished);
      expect(
          parsePlaybackOutcome(<String>['stopped']), PlaybackOutcome.stopped);
      expect(parsePlaybackOutcome(<String>['failed']), PlaybackOutcome.failed);
    });

    test('throws a protocol error for unknown output', () {
      expect(
        () => parsePlaybackOutcome(<String>['what']),
        throwsA(isA<EngineException>().having(
          (error) => error.kind,
          'kind',
          EngineErrorKind.protocol,
        )),
      );
    });
  });
}
