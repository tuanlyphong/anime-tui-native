import 'dart:io';

import 'package:anime_tui_native/core/errors/engine_exception.dart';
import 'package:anime_tui_native/core/logging/app_logger.dart';
import 'package:anime_tui_native/engine/mobile/mobile_engine.dart';
import 'package:anime_tui_native/engine/mobile/mobile_history_store.dart';
import 'package:anime_tui_native/engine/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late MobileHistoryStore history;
  late _FakeSearchSource searchSource;
  late _FakePageBrowser browser;
  late MobileEngine engine;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anime-tui-mobile');
    history = MobileHistoryStore(
      filePath: '${directory.path}/mobile-history.json',
    );
    searchSource = _FakeSearchSource();
    browser = _FakePageBrowser();
    engine = MobileEngine(
      searchSource: searchSource,
      browser: browser,
      history: history,
      logger: AppLogger(maxEntries: 50),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await directory.delete(recursive: true);
  });

  test('search delegates to the HTTP source', () async {
    final results = await engine.search('naruto');

    expect(searchSource.queries, <String>['naruto']);
    expect(results.single.title, 'Naruto');
  });

  test('episodes mark the latest history episode as preferred', () async {
    await history.add(
      title: 'Naruto',
      url: 'https://live.test/phim/naruto',
      poster: '',
      latestEpisode: 'Tập 2',
    );
    browser.rows = <Object?>[
      <String, Object?>{
        'title': 'Tập 1',
        'name': 'Tập 1',
        'url': 'https://live.test/phim/naruto/tap-1-111.html',
      },
      <String, Object?>{
        'title': 'Tập 2',
        'name': 'Tập 2',
        'url': 'https://live.test/phim/naruto/tap-2-222.html',
      },
    ];

    final episodes = await engine.episodes('https://live.test/phim/naruto');

    expect(browser.episodeRequests, <String>[
      'https://live.test/phim/naruto',
    ]);
    expect(episodes[1].preferred, isTrue);
    expect(episodes.first.preferred, isFalse);
  });

  test('an explicit preferred URL overrides history', () async {
    await history.add(
      title: 'Naruto',
      url: 'https://live.test/phim/naruto',
      poster: '',
      latestEpisode: 'Tập 1',
    );
    browser.rows = <Object?>[
      <String, Object?>{
        'title': 'Tập 1',
        'name': 'Tập 1',
        'url': 'https://live.test/phim/naruto/tap-1-111.html',
      },
      <String, Object?>{
        'title': 'Tập 2',
        'name': 'Tập 2',
        'url': 'https://live.test/phim/naruto/tap-2-222.html',
      },
    ];

    final episodes = await engine.episodes(
      'https://live.test/phim/naruto',
      preferredEpisodeUrl: 'https://live.test/phim/naruto/tap-2-222.html',
    );

    expect(episodes.last.preferred, isTrue);
  });

  test('resolveStream delegates to the headless browser', () async {
    final link = await engine.resolveStream(
      'https://live.test/phim/naruto/tap-1-111.html',
    );

    expect(link, 'https://abyssplayer.com/embed/abc');
    expect(browser.streamRequests, <String>[
      'https://live.test/phim/naruto/tap-1-111.html',
    ]);
  });

  test('history is stored locally and supports completion', () async {
    await engine.addHistory(
      title: 'Naruto',
      url: 'https://live.test/phim/naruto',
      poster: 'https://cdn.test/naruto.jpg',
      latestEpisode: 'Tập 3',
    );

    var entries = await engine.history(completed: false);
    expect(entries.single.latestEpisode, 'Tập 3');

    await engine.setCompleted('https://live.test/phim/naruto', completed: true);

    expect(await engine.history(completed: false), isEmpty);
    entries = await engine.history(completed: true);
    expect(entries.single.completed, isTrue);
  });

  test('health is always ready because the engine is built in', () async {
    final health = await engine.checkHealth();

    expect(health.ready, isTrue);
    expect(health.message, contains('Mobile engine'));
  });

  test('play must go through the in-app playback session', () async {
    expect(
      () => engine.play(const PlaybackRequest(
        streamUrl: 'https://abyssplayer.com/embed/abc',
        animeUrl: 'https://live.test/phim/naruto',
        episodeUrl: 'https://live.test/phim/naruto/tap-1-111.html',
        label: 'Naruto — Tập 1',
      )),
      throwsA(
        isA<EngineException>().having(
          (error) => error.kind,
          'kind',
          EngineErrorKind.unsupportedPlatform,
        ),
      ),
    );
  });

  test('dispose releases the browser', () async {
    await engine.dispose();

    expect(browser.disposed, isTrue);
  });
}

class _FakeSearchSource implements MobileSearchSource {
  final List<String> queries = <String>[];

  @override
  Future<List<AnimeSummary>> search(String query) async {
    queries.add(query);
    return const <AnimeSummary>[
      AnimeSummary(title: 'Naruto', url: 'https://live.test/phim/naruto'),
    ];
  }
}

class _FakePageBrowser implements MobilePageBrowser {
  List<Object?> rows = <Object?>[];
  final List<String> episodeRequests = <String>[];
  final List<String> streamRequests = <String>[];
  bool disposed = false;

  @override
  Future<List<Object?>> fetchEpisodeRows(String animeUrl) async {
    episodeRequests.add(animeUrl);
    return rows;
  }

  @override
  Future<String> resolvePlayer(String episodeUrl) async {
    streamRequests.add(episodeUrl);
    return 'https://abyssplayer.com/embed/abc';
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
