import 'dart:io';

/// Platform-correct locations for configuration and state files.
///
/// The app deliberately avoids `path_provider` so the whole data layer stays
/// testable in plain Dart and the desktop build has one less plugin.
abstract final class AppPaths {
  static const String appDirectoryName = 'anime-tui-native';

  static String get _home {
    final env = Platform.environment;
    return env['HOME'] ?? env['USERPROFILE'] ?? Directory.current.path;
  }

  static String get _configHome {
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

  /// Directory that holds the rolling log file.
  static String get stateDirectory =>
      '$_stateHome${Platform.pathSeparator}$appDirectoryName';

  static String get settingsFile =>
      '$configDirectory${Platform.pathSeparator}settings.json';

  static String get logFile =>
      '$stateDirectory${Platform.pathSeparator}app.log';

  /// File that stores watch history (exported/imported manually).
  static String get historyFile =>
      '$stateDirectory${Platform.pathSeparator}history.json';

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
