import 'dart:io';

import '../app/app_settings.dart';
import 'java_runtime.dart';

/// Immutable, validated configuration for the Node.js engine process.
class EngineConfig {
  EngineConfig({
    required this.nodeExecutable,
    required this.scriptPath,
    required this.workingDirectory,
    required this.networkTimeout,
    Map<String, String> environment = const <String, String>{},
    this.javaHome,
    this.javaExecutable,
    this.javaVersion,
    this.javaMajorVersion,
  }) : environment = Map<String, String>.unmodifiable(environment);

  final String nodeExecutable;
  final String scriptPath;
  final String workingDirectory;
  final Duration networkTimeout;

  /// Extra environment variables passed on top of the parent environment.
  final Map<String, String> environment;

  /// The Java 21+ runtime used for `abyss-dl.jar`, when one was found.
  final String? javaHome;
  final String? javaExecutable;
  final String? javaVersion;
  final int? javaMajorVersion;

  factory EngineConfig.fromSettings(AppSettings settings) {
    final scriptPath = _absolute(settings.enginePath);
    final workingDirectory = settings.workingDirectory.trim().isNotEmpty
        ? _absolute(settings.workingDirectory.trim())
        : (scriptPath.isNotEmpty
            ? File(scriptPath).parent.absolute.path
            : Directory.current.path);

    final environment = <String, String>{};
    // abyss-dl.jar requires Java 21+. Ensure the engine uses a Java 21+
    // runtime even when the parent environment points at an older JDK
    // (SDKMAN's `current` is a common source of Java 17).
    final java = JavaRuntime.discover();
    if (java != null) {
      environment['JAVA_HOME'] = java.home;
      // Absolute path: the Node child inherits this, and abyss-progressive.js
      // uses it instead of trusting PATH order.
      environment['ANIME_TUI_JAVA'] = java.executable;
      final javaBin = File(java.executable).parent.path;
      final existingPath = Platform.environment['PATH'] ?? '';
      environment['PATH'] = existingPath.isEmpty
          ? javaBin
          : '$javaBin${Platform.pathSeparator}$existingPath';
    }
    if (settings.abyssJar.trim().isNotEmpty) {
      environment['ABYSS_DL_JAR'] = _absolute(settings.abyssJar.trim());
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
      javaHome: java?.home,
      javaExecutable: java?.executable,
      javaVersion: java?.version,
      javaMajorVersion: java?.majorVersion,
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
    String? javaHome,
    String? javaExecutable,
    String? javaVersion,
    int? javaMajorVersion,
  }) =>
      EngineConfig(
        nodeExecutable: nodeExecutable ?? this.nodeExecutable,
        scriptPath: scriptPath ?? this.scriptPath,
        workingDirectory: workingDirectory ?? this.workingDirectory,
        networkTimeout: networkTimeout ?? this.networkTimeout,
        environment: environment ?? this.environment,
        javaHome: javaHome ?? this.javaHome,
        javaExecutable: javaExecutable ?? this.javaExecutable,
        javaVersion: javaVersion ?? this.javaVersion,
        javaMajorVersion: javaMajorVersion ?? this.javaMajorVersion,
      );
}
