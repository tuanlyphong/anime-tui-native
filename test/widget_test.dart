import 'dart:async';

import 'package:anime_tui_native/app/app.dart';
import 'package:anime_tui_native/app/app_settings.dart';
import 'package:anime_tui_native/core/logging/app_logger.dart';
import 'package:anime_tui_native/engine/models.dart';
import 'package:anime_tui_native/state/app_controller.dart';
import 'package:anime_tui_native/ui/chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_engine.dart';

void main() {
  testWidgets('browse, select and play an episode',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final engine = FakeEngine();
    final controller = AppController.create(
      engine: engine,
      settings: const AppSettings(enginePath: '/tmp/anime.js'),
      store: MemorySettingsStore(),
      logger: AppLogger(maxEntries: 100),
    );
    await controller.initialize();

    await tester.pumpWidget(AnimeTuiApp(controller: controller));
    await tester.pumpAndSettle();

    // Shell chrome.
    expect(find.text('Anime TUI'), findsOneWidget);
    expect(find.text('Search results'), findsOneWidget);
    expect(find.text('No active playback'), findsOneWidget);
    expect(find.text('Engine ready'), findsWidgets);

    // Search.
    await tester.enterText(find.byType(TextField).first, 'naruto');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Naruto'), findsOneWidget);
    expect(find.text('One Piece'), findsOneWidget);

    // Select a result -> episodes load in the right pane.
    await tester.tap(find.text('Naruto'));
    await tester.pumpAndSettle();

    expect(find.text('Tập 1'), findsWidgets);
    expect(find.text('Tập 2'), findsWidgets);
    expect(find.text('Resume'), findsOneWidget);

    // Play an episode.
    await tester.tap(find.text('Tập 1').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(engine.playRequests, hasLength(1));
    expect(engine.historyAdds, isNotEmpty);
    expect(find.text('Finished'), findsWidgets);

    // Unmount before disposing the controller so no listener fires afterwards.
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('shows the engine setup banner when the engine is unavailable',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController.create(
      engine: _UnavailableEngine(),
      settings: const AppSettings(),
      store: MemorySettingsStore(),
      logger: AppLogger(maxEntries: 100),
    );
    await controller.initialize();

    await tester.pumpWidget(AnimeTuiApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.textContaining('Engine not configured'), findsWidgets);
    expect(find.text('Open settings'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('narrow screens use bottom navigation and no desktop chrome',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final engine = FakeEngine();
    final controller = AppController.create(
      engine: engine,
      settings: const AppSettings(enginePath: '/tmp/anime.js'),
      store: MemorySettingsStore(),
      logger: AppLogger(maxEntries: 100),
    );
    await controller.initialize();

    await tester.pumpWidget(AnimeTuiApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(AppSidebar), findsNothing);
    expect(find.text('Search results'), findsOneWidget);
    expect(find.text('No active playback'), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Continue watching'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('narrow screens show the playback bar as soon as play starts',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final gate = Completer<void>();
    final engine = FakeEngine()..playbackGate = gate;
    final controller = AppController.create(
      engine: engine,
      settings: const AppSettings(enginePath: '/tmp/anime.js'),
      store: MemorySettingsStore(),
      logger: AppLogger(maxEntries: 100),
    );
    await controller.initialize();

    await tester.pumpWidget(AnimeTuiApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.byType(PlaybackBar), findsNothing);

    unawaited(controller.playback.play(
      anime: const AnimeSummary(
        title: 'Naruto',
        url: 'https://example.com/phim/naruto',
      ),
      episode: const Episode(
        title: 'Tập 1',
        url: 'https://example.com/tap-1.html',
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(PlaybackBar), findsOneWidget);
    expect(find.text('Playing'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

class _UnavailableEngine extends FakeEngine {
  @override
  Future<EngineHealth> checkHealth() async => EngineHealth.unavailable(
        'Engine not configured. Open Settings and choose anime.js.',
      );
}
