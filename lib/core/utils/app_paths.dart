import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Platform-correct locations for configuration and state files.
///
/// Desktop paths are derived from the environment. Android uses the app's
/// private support directory, which requires an async lookup; call
/// [initialize] once before reading any path on mobile.
abstract final class AppPaths {
  static const String appDirectoryName = 'anime-tui-native';

  static bool _initialized = false;
  static String? _mobileSupportDirectory;

  /// Resolve platform directories that require plugins. Safe to call on every
  /// platform; desktop is a no-op.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final directory = await getApplicationSupportDirectory();
      _mobileSupportDirectory = directory.path;
    } on Object {
      // Keep the HOME-based fallback usable if the plugin is unavailable.
      _mobileSupportDirectory = null;
    }
  }

  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  static String get _home {
    final env = Platform.environment;
    return env['HOME'] ?? env['USERPROFILE'] ?? Directory.current.path;
  }

  static String get _configHome {
    if (_isMobile) {
      final base = _mobileSupportDirectory ?? _home;
      return '$base${Platform.pathSeparator}config';
    }
    final env = Platform.environment;
    if (Platform.isWindows) {
      return env['APPDATA'] ?? '$_home\\AppData\\Roaming';
    }
    if (Platform.isMacOS) {
      return '$_home/Library/Application Support';
    }
    return env['XDG_CONFIG_HOME'] ?? '$_home/.config';
  }

  static String get _stateHome {
    if (_isMobile) {
      final base = _mobileSupportDirectory ?? _home;
      return '$base${Platform.pathSeparator}state';
    }
    final env = Platform.environment;
    if (Platform.isWindows) {
      return env['LOCALAPPDATA'] ?? '$_home\\AppData\\Local';
    }
    if (Platform.isMacOS) {
      return '$_home/Library/Logs';
    }
    return env['XDG_STATE_HOME'] ?? '$_home/.local/state';
  }

  /// Directory that holds `settings.json`.
  static String get configDirectory =>
      '$_configHome${Platform.pathSeparator}$appDirectoryName';

  /// Directory that holds the rolling log file and local history.
  static String get stateDirectory =>
      '$_stateHome${Platform.pathSeparator}$appDirectoryName';

  static String get settingsFile =>
      '$configDirectory${Platform.pathSeparator}settings.json';

  static String get logFile =>
      '$stateDirectory${Platform.pathSeparator}app.log';

  /// File that stores watch history (exported/imported manually).
  static String get historyFile =>
      '$stateDirectory${Platform.pathSeparator}history.json';

  /// History owned by the Android engine.
  static String get mobileHistoryFile =>
      '$stateDirectory${Platform.pathSeparator}mobile-history.json';

  /// Creates [directory] (and parents) if needed. Returns null on failure so
  /// callers can log a warning instead of crashing during startup.
  static String? ensureDirectory(String directory) {
    try {
      Directory(directory).createSync(recursive: true);
      return directory;
    } on FileSystemException {
      return null;
    }
  }
}
