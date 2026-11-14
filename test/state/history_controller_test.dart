import 'dart:async';
import 'dart:convert';

import 'package:anime_tui_native/core/errors/engine_exception.dart';
import 'package:anime_tui_native/core/logging/app_logger.dart';
import 'package:anime_tui_native/state/history_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_engine.dart';

void main() {
  late FakeEngine engine;
  late HistoryController controller;

  setUp(() {
    engine = FakeEngine();
    controller = HistoryController(
      engine: engine,
      logger: AppLogger(maxEntries: 50),
    );
  });

  tearDown(() {
    controller.dispose();
  });

  test('loads in-progress and completed lists separately', () async {
    await controller.load(completed: false);
    await controller.load(completed: true);

    expect(controller.entries(completed: false), hasLength(1));
    expect(controller.entries(completed: true), isEmpty);
  });

  test('marking complete refreshes both lists', () async {
    await controller.load(completed: false);
    final entry = controller.entries(completed: false).single;

    await controller.setCompleted(entry, completed: true);

    expect(engine.completionCalls[entry.url], isTrue);
    expect(controller.entries(completed: false), isEmpty);
    expect(controller.entries(completed: true), hasLength(1));
  });

  test('load errors are exposed without clearing previous state', () async {
    await controller.load(completed: false);
    engine.historyError = EngineException(
      EngineErrorKind.exitFailure,
      'history read failed',
      exitCode: 1,
    );

    await controller.load(completed: false, force: true);

    expect(controller.error(completed: false), isNotNull);
    expect(controller.entries(completed: false), hasLength(1));
  });

  test('a load from a replaced engine is discarded', () async {
    engine.historyGate = Completer<void>();
    final staleLoad = controller.load(completed: false, force: true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.isLoading(completed: false), isTrue);

    controller.updateEngine(FakeEngine());
    engine.historyGate!.complete();
    await staleLoad;

    expect(controller.hasLoaded(completed: false), isFalse);
    expect(controller.entries(completed: false), isEmpty);
  });

  test('imports history through the engine so it survives a reload', () async {
    await controller.load(completed: false);
    const importedUrl = 'https://example.com/phim/one-piece';

    final result = await controller.importHistoryContent(jsonEncode(
      <Map<String, Object?>>[
        <String, Object?>{
          'title': 'One Piece',
          'url': importedUrl,
          'poster': '',
          'latestEpisode': 'Tập 10',
          'completed': false,
        },
      ],
    ));

    expect(result.imported, 1);
    expect(engine.historyImports.single.single.url, importedUrl);
    expect(
      controller.entries(completed: false).map((entry) => entry.url),
      contains(importedUrl),
    );

    // A fresh controller reads from the same engine store, like a relaunch.
    final reopened = HistoryController(
      engine: engine,
      logger: AppLogger(maxEntries: 50),
    );
    await reopened.load(completed: false);
    expect(
      reopened.entries(completed: false).map((entry) => entry.url),
      contains(importedUrl),
    );
    reopened.dispose();
  });
}
