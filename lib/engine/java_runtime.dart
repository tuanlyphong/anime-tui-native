import 'dart:io';

/// A Java runtime installed on this machine.
///
/// The Abyss downloader (`abyss-dl.jar`) is compiled for Java 21 (class file
/// version 65). Discovering a runtime by name alone is not enough: SDKMAN and
/// other version managers commonly export a `JAVA_HOME` that points at an
/// older JDK. This class therefore validates the *version* of every candidate
/// before it is handed to the Node engine.
class JavaRuntime {
  const JavaRuntime({
    required this.home,
    required this.executable,
    required this.version,
    required this.majorVersion,
  });

  /// Minimum runtime supported by `abyss-dl.jar`.
  static const int minimumMajorVersion = 21;

  final String home;
  final String executable;

  /// Full version label, e.g. `21.0.12.1` or `17.0.21`.
  final String version;
  final int majorVersion;

  bool get isSupported => majorVersion >= minimumMajorVersion;

  /// Returns the highest-priority Java 21+ runtime, or null when none exists.
  ///
  /// Priority is: explicit override (`ANIME_TUI_JAVA` / `ANIME_TUI_JAVA_HOME`),
  /// `JAVA_HOME`, SDKMAN, platform package directories, then the `java` that
  /// would be resolved from `PATH`. Candidates that point at an older JDK are
  /// skipped instead of silently winning.
  static JavaRuntime? discover({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    for (final home in _candidateHomes(env)) {
      final runtime = _fromHome(home);
      if (runtime != null && runtime.isSupported) return runtime;
    }
    return null;
  }

  /// Convenience wrapper used when only the executable is known.
  static JavaRuntime? fromExecutable(String executable) {
    final trimmed = executable.trim();
    if (trimmed.isEmpty || !File(trimmed).existsSync()) return null;
    return _fromHome(_homeOfExecutable(trimmed));
  }

  static List<String> _candidateHomes(Map<String, String> env) {
    final homes = <String>[];
    final seen = <String>{};

    void addHome(String? value) {
      final candidate = value?.trim();
      if (candidate == null || candidate.isEmpty) return;
      final normalized = _normalize(candidate);
      if (normalized.isEmpty || !seen.add(normalized)) return;
      homes.add(normalized);
    }

    void addExecutable(String? value) {
      final candidate = value?.trim();
      if (candidate == null || candidate.isEmpty) return;
      if (!File(candidate).existsSync()) return;
      addHome(_homeOfExecutable(candidate));
    }

    void addSubdirectories(String parent, {String suffix = ''}) {
      try {
        final directories = Directory(parent)
            .listSync(followLinks: true)
            .whereType<Directory>()
            .map((directory) => directory.path)
            .toList()
          // Prefer the oldest compatible runtime (21 before 22/27).
          ..sort((a, b) => a.compareTo(b));
        for (final directory in directories) {
          addHome('$directory$suffix');
        }
      } on FileSystemException {
        // The directory does not exist on this platform.
      }
    }

    final home = env['HOME'] ?? env['USERPROFILE'];

    // Explicit user overrides win, but are still version-checked.
    addExecutable(env['ANIME_TUI_JAVA']);
    addHome(env['ANIME_TUI_JAVA_HOME']);
    addHome(env['JAVA_HOME']);

    if (home != null && home.isNotEmpty) {
      final sdkman = '$home${Platform.pathSeparator}.sdkman'
          '${Platform.pathSeparator}candidates${Platform.pathSeparator}java';
      addHome('$sdkman${Platform.pathSeparator}current');
      addSubdirectories(sdkman);
    }

    if (Platform.isLinux) {
      addSubdirectories('/usr/lib/jvm');
      addHome('/usr/lib/jvm/java-21-openjdk');
      addHome('/usr/lib/jvm/java-21-openjdk-amd64');
    } else if (Platform.isMacOS) {
      addSubdirectories(
        '/Library/Java/JavaVirtualMachines',
        suffix: '${Platform.pathSeparator}Contents'
            '${Platform.pathSeparator}Home',
      );
      addSubdirectories('/opt/homebrew/opt');
      addSubdirectories('/usr/local/opt');
      addHome(
        '/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home',
      );
    } else if (Platform.isWindows) {
      final programFiles = env['ProgramFiles'];
      final localAppData = env['LOCALAPPDATA'];
      if (programFiles != null && programFiles.isNotEmpty) {
        addSubdirectories('$programFiles${Platform.pathSeparator}Java');
        addSubdirectories(
          '$programFiles${Platform.pathSeparator}Eclipse Adoptium',
        );
        addSubdirectories(
          '$programFiles${Platform.pathSeparator}Microsoft',
        );
        addSubdirectories(
          '$programFiles${Platform.pathSeparator}Amazon Corretto',
        );
      }
      if (localAppData != null && localAppData.isNotEmpty) {
        addSubdirectories(
          '$localAppData${Platform.pathSeparator}Programs'
          '${Platform.pathSeparator}Eclipse Adoptium',
        );
      }
    }

    // Last resort: the java executable that the parent PATH would resolve.
    for (final directory in _pathDirectories(env)) {
      final executable = '$directory${Platform.pathSeparator}'
          '${Platform.isWindows ? 'java.exe' : 'java'}';
      addExecutable(executable);
    }

    return homes;
  }

  static Iterable<String> _pathDirectories(Map<String, String> env) sync* {
    final path = env['PATH'];
    if (path == null || path.isEmpty) return;
    final separator = Platform.isWindows ? ';' : ':';
    for (final entry in path.split(separator)) {
      final directory = entry.trim();
      if (directory.isNotEmpty) yield directory;
    }
  }

  static JavaRuntime? _fromHome(String home) {
    final executable = _executableFor(home);
    if (!File(executable).existsSync()) return null;

    // Prefer the JDK's `release` file: no subprocess needed and it is
    // available even if the runtime cannot start (e.g. a broken symlink).
    final releaseVersion = _versionFromReleaseFile(home);
    if (releaseVersion != null) {
      final major = _majorVersion(releaseVersion);
      if (major != null) {
        return JavaRuntime(
          home: home,
          executable: executable,
          version: releaseVersion,
          majorVersion: major,
        );
      }
    }

    final reported = _versionFromProcess(executable);
    if (reported == null) return null;
    final major = _majorVersion(reported);
    if (major == null) return null;
    return JavaRuntime(
      home: home,
      executable: executable,
      version: reported,
      majorVersion: major,
    );
  }

  static String _executableFor(String home) =>
      '$home${Platform.pathSeparator}bin${Platform.pathSeparator}'
      '${Platform.isWindows ? 'java.exe' : 'java'}';

  static String? _versionFromReleaseFile(String home) {
    try {
      final release = File(
        '$home${Platform.pathSeparator}release',
      );
      if (!release.existsSync()) return null;
      final match = RegExp(
        r'JAVA_VERSION\s*=\s*"([^"]+)"',
      ).firstMatch(release.readAsStringSync());
      return match?.group(1)?.trim();
    } on FileSystemException {
      return null;
    }
  }

  static String? _versionFromProcess(String executable) {
    try {
      final result = Process.runSync(
        executable,
        const <String>['-version'],
        stdoutEncoding: const SystemEncoding(),
        stderrEncoding: const SystemEncoding(),
        runInShell: false,
      );
      final output = '${result.stdout}\n${result.stderr}';
      return RegExp(r'version\s+"([^"]+)"')
          .firstMatch(output)
          ?.group(1)
          ?.trim();
    } on ProcessException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Extracts the feature version from labels such as `21.0.12`, `21-ea`, or
  /// the legacy `1.8.0_402`.
  static int? _majorVersion(String version) {
    final legacy = RegExp(r'^1\.(\d+)').firstMatch(version);
    if (legacy != null) return int.tryParse(legacy.group(1)!);
    final match = RegExp(r'^(\d+)').firstMatch(version);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static String _homeOfExecutable(String executable) {
    try {
      final resolved = File(executable).resolveSymbolicLinksSync();
      final bin = File(resolved).parent;
      if (bin.path.endsWith('${Platform.pathSeparator}bin')) {
        return bin.parent.path;
      }
    } on FileSystemException {
      // Fall through to the unresolved path.
    }
    return File(executable).parent.parent.path;
  }

  static String _normalize(String path) {
    try {
      return File(path).absolute.path;
    } on FileSystemException {
      return path;
    }
  }
}
