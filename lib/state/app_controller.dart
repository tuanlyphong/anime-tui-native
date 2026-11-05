import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/logging/app_logger.dart';
import '../engine/cli_engine_transport.dart';
import '../engine/engine_client.dart';
import '../engine/engine_config.dart';
import '../engine/models.dart';
import '../app/app_settings.dart';
import 'browser_controller.dart';
import 'history_controller.dart';
import 'playback_controller.dart';

/// Composition root for the app's state layer.
///
/// The UI depends on this single object (through [AppScope]); it owns the
/// engine client, settings, health, and the three focused controllers. It can
/// be constructed with a fake [AnimeEngine] in widget tests.
class AppController extends ChangeNotifier {
  AppController._({
    required AnimeEngine engine,
    required this.settings,
    required this.store,
    required this.logger,
  })  : _engine = engine,
        config = EngineConfig.fromSettings(settings) {
    browser = BrowserController(engine: engine, logger: logger);
    playback = PlaybackController(engine: engine, logger: logger);
    history = HistoryController(engine: engine, logger: logger);
  }

  factory AppController.create({
    required AppSettings settings,
    required SettingsStore store,
    AppLogger? logger,
    AnimeEngine? engine,
  }) {
    final log = logger ?? AppLogger.instance;
    final effectiveEngine = engine ??
        EngineClient(
          transport: CliEngineTransport(
            config: EngineConfig.fromSettings(settings),
            logger: log,
          ),
          config: EngineConfig.fromSettings(settings),
          logger: log,
        );
    return AppController._(
      engine: effectiveEngine,
      settings: settings,
      store: store,
      logger: log,
    );
  }

  final SettingsStore store;
  final AppLogger logger;

  AppSettings settings;
  EngineConfig config;

  AnimeEngine _engine;

  late final BrowserController browser;
  late final PlaybackController playback;
  late final HistoryController history;

  EngineHealth? _health;
  bool _initializing = true;
  String? _startupError;
  bool _disposed = false;
  bool _initialized = false;

  EngineHealth? get health => _health;
  bool get isInitializing => _initializing;
  String? get startupError => _startupError;
  AnimeEngine get engine => _engine;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _initializing = true;
    _notify();
    try {
      _health = await _engine.checkHealth();
      if (_health?.ready == true) {
        await history.load(completed: false);
      }
    } on Object catch (error, stackTrace) {
      _startupError = error.toString();
      logger.error(
        'Startup health check failed',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _initializing = false;
      _notify();
    }
  }

  Future<void> refreshHealth() async {
    _health = await _engine.checkHealth();
    if (_health?.ready == true && !history.hasLoaded(completed: false)) {
      await history.load(completed: false, force: true);
    }
    _notify();
  }

  Future<EngineHealth> testSettings(AppSettings candidate) async {
    final probe = CliEngineTransport(
      config: EngineConfig.fromSettings(candidate),
      logger: logger,
    );
    try {
      return await probe.healthCheck();
    } finally {
      await probe.dispose();
    }
  }

  Future<void> applySettings(AppSettings next) async {
    _initializing = true;
    _startupError = null;
    _notify();

    try {
      await store.save(next);
      settings = next;
      config = EngineConfig.fromSettings(next);

      final previous = _engine;
      final nextEngine = EngineClient(
        transport: CliEngineTransport(config: config, logger: logger),
        config: config,
        logger: logger,
      );

      _engine = nextEngine;
      browser.updateEngine(nextEngine);
      playback.updateEngine(nextEngine);
      history.updateEngine(nextEngine);
      _health = null;
      _notify();

      unawaited(previous.dispose());

      _health = await nextEngine.checkHealth();
      if (_health?.ready == true) {
        await history.load(completed: false, force: true);
      }
    } on Object catch (error, stackTrace) {
      _startupError = error.toString();
      logger.error(
        'Applying settings failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      _initializing = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    browser.dispose();
    playback.dispose();
    history.dispose();
    unawaited(_engine.dispose());
    super.dispose();
  }
}
