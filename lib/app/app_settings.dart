import 'dart:convert';
import 'dart:io';

import '../core/logging/app_logger.dart';
import '../core/utils/app_paths.dart';

/// User-editable engine configuration, persisted between launches.
class AppSettings {
  const AppSettings({
    this.enginePath = '',
    this.nodeExecutable = 'node',
    this.workingDirectory = '',
    this.networkTimeoutSeconds = 120,
    this.quality = 'h',
    this.progressivePlayback = true,
    this.abyssJar = '',
    this.proxy = '',
    this.player = 'mpv',
  });

  final String enginePath;
  final String nodeExecutable;
  final String workingDirectory;
  final int networkTimeoutSeconds;

  /// `h`, `m`, or `l`.
  final String quality;
  final bool progressivePlayback;
  final String abyssJar;
  final String proxy;
  final String player;

  factory AppSettings.defaults() {
    // Android uses the built-in mobile engine; probing desktop engine, Node,
    // Java, and jar paths is unnecessary and noisy.
    if (Platform.isAndroid || Platform.isIOS) return const AppSettings();
    final env = Platform.environment;
    return AppSettings(
      enginePath: env['ANIME_TUI_ENGINE_PATH']?.trim().isNotEmpty == true
          ? env['ANIME_TUI_ENGINE_PATH']!.trim()
          : discoverEnginePath(),
      nodeExecutable: env['ANIME_TUI_NODE']?.trim().isNotEmpty == true
          ? env['ANIME_TUI_NODE']!.trim()
          : 'node',
      abyssJar: env['ABYSS_DL_JAR']?.trim().isNotEmpty == true
          ? env['ABYSS_DL_JAR']!.trim()
          : discoverAbyssJarPath(),
      proxy: env['ANIME_TUI_PROXY'] ?? '',
      player: env['PLAYER'] ?? 'mpv',
      quality:
          _validQuality(env['ABYSS_QUALITY']) ? env['ABYSS_QUALITY']! : 'h',
      progressivePlayback: env['ABYSS_PROGRESSIVE'] != '0',
      networkTimeoutSeconds: 120,
    );
  }

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final defaults = AppSettings.defaults();
    int intValue(Object? value, int fallback) =>
        value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
    bool boolValue(Object? value, bool fallback) =>
        value is bool ? value : fallback;
    // An empty persisted value must fall back to the discovered default, not
    // pin the field to an empty string forever.
    String? nonEmpty(Object? value) {
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    // A settings file copied from another machine (or an older install) may
    // point at an engine/jar that no longer exists. Prefer the built-in copy
    // discovered next to the executable instead of starting up broken.
    String pathOrDefault(String? persisted, String discovered) {
      final value = nonEmpty(persisted);
      if (value == null) return discovered;
      return File(value).existsSync() ? value : discovered;
    }

    return AppSettings(
      enginePath:
          pathOrDefault(json['enginePath'] as String?, defaults.enginePath),
      nodeExecutable:
          nonEmpty(json['nodeExecutable']) ?? defaults.nodeExecutable,
      workingDirectory: nonEmpty(json['workingDirectory']) ?? '',
      networkTimeoutSeconds: intValue(
        json['networkTimeoutSeconds'],
        defaults.networkTimeoutSeconds,
      ).clamp(15, 900),
      quality: _validQuality(json['quality'] as String?)
          ? json['quality'] as String
          : defaults.quality,
      progressivePlayback: boolValue(
        json['progressivePlayback'],
        defaults.progressivePlayback,
      ),
      abyssJar: pathOrDefault(
        json['abyssJar'] as String?,
        defaults.abyssJar,
      ),
      proxy: nonEmpty(json['proxy']) ?? defaults.proxy,
      player: nonEmpty(json['player']) ?? defaults.player,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'enginePath': enginePath,
        'nodeExecutable': nodeExecutable,
        'workingDirectory': workingDirectory,
        'networkTimeoutSeconds': networkTimeoutSeconds,
        'quality': quality,
        'progressivePlayback': progressivePlayback,
        'abyssJar': abyssJar,
        'proxy': proxy,
        'player': player,
      };

  AppSettings copyWith({
    String? enginePath,
    String? nodeExecutable,
    String? workingDirectory,
    int? networkTimeoutSeconds,
    String? quality,
    bool? progressivePlayback,
    String? abyssJar,
    String? proxy,
    String? player,
  }) =>
      AppSettings(
        enginePath: enginePath ?? this.enginePath,
        nodeExecutable: nodeExecutable ?? this.nodeExecutable,
        workingDirectory: workingDirectory ?? this.workingDirectory,
        networkTimeoutSeconds:
            networkTimeoutSeconds ?? this.networkTimeoutSeconds,
        quality: quality ?? this.quality,
        progressivePlayback: progressivePlayback ?? this.progressivePlayback,
        abyssJar: abyssJar ?? this.abyssJar,
        proxy: proxy ?? this.proxy,
        player: player ?? this.player,
      );

  static bool _validQuality(String? value) =>
      const {'h', 'm', 'l'}.contains(value);

  /// Looks for the engine in the locations used during development and in a
  /// packaged desktop install. Returns an empty string when nothing is found —
  /// the UI then shows the "configure the engine" state instead of silently
  /// spawning a nonexistent process.
  static String discoverEnginePath() {
    if (Platform.isAndroid || Platform.isIOS) return '';
    final env = Platform.environment['ANIME_TUI_ENGINE_PATH'];
    if (env != null && env.trim().isNotEmpty) return env.trim();

    final cwd = Directory.current.path;
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    // Built-in engine: bundled with the project (no env var needed), then
    // next to the packaged executable for desktop installs. Release bundles
    // place the engine in an `engine/` directory beside the binary.
    final candidates = <String>[
      '$executableDir${Platform.pathSeparator}engine${Platform.pathSeparator}anime.js',
      '$executableDir${Platform.pathSeparator}..${Platform.pathSeparator}Resources${Platform.pathSeparator}engine${Platform.pathSeparator}anime.js',
      '$cwd${Platform.pathSeparator}engine${Platform.pathSeparator}anime.js',
      '$cwd${Platform.pathSeparator}anime.js',
      '$cwd${Platform.pathSeparator}..${Platform.pathSeparator}anime.js',
      '$executableDir${Platform.pathSeparator}anime.js',
      '$executableDir${Platform.pathSeparator}..${Platform.pathSeparator}Resources${Platform.pathSeparator}anime.js',
      '$cwd${Platform.pathSeparator}..${Platform.pathSeparator}anime-tui-cross${Platform.pathSeparator}anime.js',
      '${Directory(cwd).parent.path}${Platform.pathSeparator}anime-tui-cross${Platform.pathSeparator}anime.js',
    ];

    for (final candidate in candidates) {
      final normalized = _normalize(candidate);
      if (File(normalized).existsSync()) return normalized;
    }
    return '';
  }

  static String discoverAbyssJarPath() {
    if (Platform.isAndroid || Platform.isIOS) return '';
    final env = Platform.environment['ABYSS_DL_JAR'];
    if (env != null && env.trim().isNotEmpty) return env.trim();

    final cwd = Directory.current.path;
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      '$executableDir${Platform.pathSeparator}engine${Platform.pathSeparator}abyss-dl.jar',
      '$executableDir${Platform.pathSeparator}..${Platform.pathSeparator}Resources${Platform.pathSeparator}engine${Platform.pathSeparator}abyss-dl.jar',
      '$cwd${Platform.pathSeparator}engine${Platform.pathSeparator}abyss-dl.jar',
      '$cwd${Platform.pathSeparator}abyss-dl.jar',
      '$cwd${Platform.pathSeparator}..${Platform.pathSeparator}abyss-dl.jar',
      '$cwd${Platform.pathSeparator}lib${Platform.pathSeparator}abyss-dl.jar',
      '$cwd${Platform.pathSeparator}assets${Platform.pathSeparator}abyss-dl.jar',
      '$executableDir${Platform.pathSeparator}abyss-dl.jar',
      '$executableDir${Platform.pathSeparator}..${Platform.pathSeparator}Resources${Platform.pathSeparator}abyss-dl.jar',
      '${Directory(cwd).parent.path}${Platform.pathSeparator}anime-tui${Platform.pathSeparator}abyss-dl.jar',
    ];

    for (final candidate in candidates) {
      final normalized = _normalize(candidate);
      if (File(normalized).existsSync()) return normalized;
    }
    return '';
  }

  static String _normalize(String path) {
    final segments = <String>[];
    for (final segment in path.split(Platform.pathSeparator)) {
      if (segment == '..') {
        if (segments.isNotEmpty && segments.last != '..') {
          segments.removeLast();
        } else {
          segments.add(segment);
        }
      } else if (segment != '.' && segment.isNotEmpty) {
        segments.add(segment);
      }
    }
    final prefix =
        path.startsWith(Platform.pathSeparator) ? Platform.pathSeparator : '';
    return '$prefix${segments.join(Platform.pathSeparator)}';
  }
}

/// Abstraction so widget tests never touch the real filesystem.
abstract interface class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

class FileSettingsStore implements SettingsStore {
  FileSettingsStore({
    String? path,
    AppLogger? logger,
  })  : _path = path ?? AppPaths.settingsFile,
        _logger = logger ?? AppLogger.instance;

  final String _path;
  final AppLogger _logger;

  @override
  Future<AppSettings> load() async {
    final file = File(_path);
    if (!await file.exists()) {
      final defaults = AppSettings.defaults();
      try {
        await save(defaults);
      } on Object catch (error, stackTrace) {
        // A read-only settings location must not prevent the app from
        // starting; the in-memory defaults are still usable.
        _logger.warning(
          'Could not create the default settings file',
          error: error,
          stackTrace: stackTrace,
          context: {'file': _path},
        );
      }
      return defaults;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('settings root is not an object');
      }
      return AppSettings.fromJson(decoded);
    } on Object catch (error, stackTrace) {
      _logger.error(
        'Could not read settings; falling back to defaults',
        error: error,
        stackTrace: stackTrace,
        context: {'file': _path},
      );
      return AppSettings.defaults();
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    final file = File(_path);
    final temporary = File('$_path.tmp');
    try {
      await file.parent.create(recursive: true);
      await temporary.writeAsString(
        const JsonEncoder.withIndent('  ').convert(settings.toJson()),
        flush: true,
      );
      try {
        await temporary.rename(_path);
      } on FileSystemException {
        // Windows cannot rename over an existing file. Remove the old copy and
        // try once more so saving works on every desktop platform.
        if (await file.exists()) {
          await file.delete();
        }
        await temporary.rename(_path);
      }
    } on Object catch (error, stackTrace) {
      // Best-effort cleanup; never mask the original failure.
      try {
        if (await temporary.exists()) await temporary.delete();
      } on Object {
        // ignore
      }
      _logger.error(
        'Could not save settings',
        error: error,
        stackTrace: stackTrace,
        context: {'file': _path},
      );
      rethrow;
    }
  }
}

/// In-memory store used by tests and by `flutter run` when persistence is not
/// desired.
class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([AppSettings? initial])
      : _settings = initial ?? AppSettings.defaults();

  AppSettings _settings;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async => _settings = settings;
}
