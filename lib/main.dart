import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_settings.dart';
import 'core/logging/app_logger.dart';
import 'core/utils/app_paths.dart';
import 'state/app_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final logger = AppLogger.instance;

  FlutterError.onError = (FlutterErrorDetails details) {
    logger.error(
      'Flutter framework error',
      error: details.exception,
      stackTrace: details.stack,
      context: {'library': details.library ?? 'unknown'},
    );
    if (kDebugMode) {
      FlutterError.presentError(details);
    }
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    logger.error('Uncaught platform error', error: error, stackTrace: stack);
    return true;
  };

  ErrorWidget.builder =
      (FlutterErrorDetails details) => _FatalErrorScreen(details: details);

  runZonedGuarded(
    () async {
      await logger.init(filePath: AppPaths.logFile);

      final store = FileSettingsStore(logger: logger);
      AppSettings settings;
      try {
        settings = await store.load();
      } on Object catch (error, stackTrace) {
        logger.error(
          'Could not load settings; using defaults',
          error: error,
          stackTrace: stackTrace,
        );
        settings = AppSettings.defaults();
      }

      final controller = AppController.create(
        settings: settings,
        store: store,
        logger: logger,
      );

      logger.info('Anime TUI starting', context: {
        'platform': PlatformDispatcher.instance.platformBrightness.name,
        'engine': settings.enginePath.isEmpty
            ? 'not configured'
            : settings.enginePath,
      });

      runApp(AnimeTuiApp(controller: controller));
      unawaited(controller.initialize());
    },
    (Object error, StackTrace stackTrace) {
      logger.error(
        'Unhandled zone error',
        error: error,
        stackTrace: stackTrace,
      );
    },
  );
}

/// Last-resort widget shown when a build fails. Keeps the app usable instead
/// of exposing Flutter's red error screen in release mode.
class _FatalErrorScreen extends StatelessWidget {
  const _FatalErrorScreen({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: const Color(0xFF0C1015),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFE2B341),
                    size: 34,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Something went wrong while drawing this screen',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The error was written to the application log. You can '
                    'continue using the rest of the app, or restart it.',
                    style: TextStyle(
                      color: Color(0xFF9AA6B2),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    details.exceptionAsString(),
                    style: const TextStyle(
                      color: Color(0xFFFF9A9A),
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
