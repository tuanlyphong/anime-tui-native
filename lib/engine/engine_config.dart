import 'dart:io';

import '../app/app_settings.dart';

/// Immutable, validated configuration for the Node.js engine process.
class EngineConfig {
  EngineConfig({
    required this.nodeExecutable,
    required this.scriptPath,
    required this.workingDirectory,
    required this.networkTimeout,
    Map<String, String> environment = const <String, String>{},
  }) : environment = Map<String, String>.unmodifiable(environment);

  final String nodeExecutable;
  final String scriptPath;
  final String workingDirectory;
  final Duration networkTimeout;

  /// Extra environment variables passed on top of the parent environment.
  final Map<String, String> environment;

  factory EngineConfig.fromSettings(AppSettings settings) {
    final scriptPath = _absolute(settings.enginePath);
    final workingDirectory = settings.workingDirectory.trim().isNotEmpty
        ? _absolute(settings.workingDirectory.trim())
        : (scriptPath.isNotEmpty
            ? File(scriptPath).parent.absolute.path
            : Directory.current.path);

    final environment = <String, String>{};
    if (settings.abyssJar.trim().isNotEmpty) {
      environment['ABYSS_DL_JAR'] = settings.abyssJar.trim();
    }
    if (settings.proxy.trim().isNotEmpty) {
      environment['ANIME_TUI_PROXY'] = settings.proxy.trim();
    }
    if (settings.player.trim().isNotEmpty) {
      environment['PLAYER'] = settings.player.trim();
    }
    environment['ABYSS_QUALITY'] = settings.quality;
    environment['ABYSS_PROGRESSIVE'] = settings.progressivePlayback ? '1' : '0';

    return EngineConfig(
      nodeExecutable: settings.nodeExecutable.trim().isEmpty
          ? 'node'
          : settings.nodeExecutable.trim(),
      scriptPath: scriptPath,
      workingDirectory: workingDirectory,
      networkTimeout: Duration(seconds: settings.networkTimeoutSeconds),
      environment: environment,
    );
  }

  static String _absolute(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '';
    if (File(trimmed).isAbsolute) return trimmed;
    return File('${Directory.current.path}${Platform.pathSeparator}$trimmed')
        .absolute
        .path;
  }

  bool get isSupportedPlatform =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  String get displayName => scriptPath.isEmpty ? 'not configured' : scriptPath;

  EngineConfig copyWith({
    String? nodeExecutable,
    String? scriptPath,
    String? workingDirectory,
    Duration? networkTimeout,
    Map<String, String>? environment,
  }) =>
      EngineConfig(
        nodeExecutable: nodeExecutable ?? this.nodeExecutable,
        scriptPath: scriptPath ?? this.scriptPath,
        workingDirectory: workingDirectory ?? this.workingDirectory,
        networkTimeout: networkTimeout ?? this.networkTimeout,
        environment: environment ?? this.environment,
      );
}
