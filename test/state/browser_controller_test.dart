import 'dart:async';

import 'package:anime_tui_native/core/errors/engine_exception.dart';
import 'package:anime_tui_native/core/logging/app_logger.dart';
import 'package:anime_tui_native/engine/models.dart';
import 'package:anime_tui_native/state/browser_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_engine.dart';

void main() {
  late FakeEngine engine;
  late BrowserController controller;

  setUp(() {
    engine = FakeEngine();
    controller = BrowserController(
      engine: engine,
      logger: AppLogger(maxEntries: 50),
    );
  });

  tearDown(() {
    controller.dispose();
  });

  test('search populates results and selectAnime loads episodes', () async {
    await controller.search('naruto');

    expect(controller.results, hasLength(2));
    expect(controller.query, 'naruto');
    expect(controller.isSearching, isFalse);

    await controller.selectAnime(controller.results.first);

    expect(controller.selectedAnime?.title, 'Naruto');
    expect(controller.episodes, hasLength(2));
    expect(controller.episodes.first.preferred, isTrue);
    expect(controller.isLoadingEpisodes, isFalse);
  });

  test('a stale search cannot overwrite a newer one', () async {
    final first = Completer<List<AnimeSummary>>();
    final second = Completer<List<AnimeSummary>>();
    engine.onSearch =
        (query) => query == 'first' ? first.future : second.future;

    final firstRequest = controller.search('first');
    final secondRequest = controller.search('second');

    second.complete(const <AnimeSummary>[
      AnimeSummary(title: 'Second result', url: 'https://example.com/second'),
    ]);
    await secondRequest;
    expect(controller.results.single.title, 'Second result');

    first.complete(const <AnimeSummary>[
      AnimeSummary(title: 'Stale result', url: 'https://example.com/stale'),
    ]);
    await firstRequest;

    expect(controller.results.single.title, 'Second result');
    expect(controller.query, 'second');
  });

  test('engine failures are exposed as typed errors', () async {
    engine.searchError = EngineException(
      EngineErrorKind.exitFailure,
      'site unreachable',
      details: 'connection reset',
      exitCode: 1,
    );

    await controller.search('naruto');

    expect(controller.searchError, isNotNull);
    expect(controller.searchError!.kind, EngineErrorKind.exitFailure);
    expect(controller.searchError!.details, contains('connection reset'));
    expect(controller.results, isEmpty);
    expect(controller.isSearching, isFalse);
  });

  test('clearSearch resets selection and results', () async {
    await controller.search('naruto');
    await controller.selectAnime(controller.results.first);

    controller.clearSearch();

    expect(controller.query, isEmpty);
    expect(controller.results, isEmpty);
    expect(controller.selectedAnime, isNull);
    expect(controller.episodes, isEmpty);
  });
}
