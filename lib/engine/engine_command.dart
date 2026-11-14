import 'models.dart';

enum EngineCommandKind {
  search,
  episodes,
  episodesProgress,
  streams,
  playEpisode,
  history,
  historyAdd,
  historyImport,
  historyComplete,
  historyUncomplete,
  abyssStream,
}

/// A normalized engine invocation.
///
/// The engine is a **one-shot CLI**, not a stdin server: every command is a new
/// `node anime.js <argv...>` process. Arguments are passed as a real argv array
/// (never interpolated into a shell), so titles containing spaces, quotes, or
/// `;` are safe.
class EngineCommand {
  EngineCommand({
    required this.kind,
    required this.arguments,
    required this.timeout,
    String? label,
  }) : label = label ?? kind.name;

  final EngineCommandKind kind;

  /// Arguments after the script path, starting with the engine subcommand.
  final List<String> arguments;

  /// Null means "run until the user stops it" (playback).
  final Duration? timeout;
  final String label;

  factory EngineCommand.search(String query, {Duration? timeout}) {
    final value = query.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(query, 'query', 'must not be empty');
    }
    return EngineCommand(
      kind: EngineCommandKind.search,
      arguments: <String>['search', value],
      timeout: timeout ?? const Duration(seconds: 90),
      label: 'search "$value"',
    );
  }

  factory EngineCommand.episodes(
    String animeUrl, {
    String? preferredEpisodeUrl,
    Duration? timeout,
  }) {
    _requireUrl(animeUrl, 'animeUrl');
    return EngineCommand(
      kind: EngineCommandKind.episodesProgress,
      arguments: <String>[
        'episodes-progress',
        animeUrl,
        if (preferredEpisodeUrl != null && preferredEpisodeUrl.isNotEmpty)
          preferredEpisodeUrl,
      ],
      timeout: timeout ?? const Duration(seconds: 180),
    );
  }

  factory EngineCommand.streams(String episodeUrl, {Duration? timeout}) {
    _requireUrl(episodeUrl, 'episodeUrl');
    return EngineCommand(
      kind: EngineCommandKind.streams,
      arguments: <String>['streams', episodeUrl],
      timeout: timeout ?? const Duration(seconds: 240),
    );
  }

  factory EngineCommand.playEpisode(
    PlaybackRequest request, {
    String player = 'mpv',
    bool progressive = true,
    String quality = 'h',
    String jar = '',
  }) {
    _requireUrl(request.streamUrl, 'streamUrl');
    _requireUrl(request.animeUrl, 'animeUrl');
    _requireUrl(request.episodeUrl, 'episodeUrl');
    if (request.label.trim().isEmpty) {
      throw ArgumentError.value(request.label, 'label', 'must not be empty');
    }

    final arguments = <String>[
      'play-episode',
      request.streamUrl,
      request.animeUrl,
      request.episodeUrl,
      request.label.trim(),
    ];
    if (player.trim().isNotEmpty) {
      arguments.addAll(<String>['--player', player.trim()]);
    }
    if (jar.trim().isNotEmpty) {
      arguments.addAll(<String>['--jar', jar.trim()]);
    }
    if (quality.trim().isNotEmpty) {
      arguments.addAll(<String>['--quality', quality.trim()]);
    }
    arguments.addAll(<String>['--progressive', progressive ? '1' : '0']);

    return EngineCommand(
      kind: EngineCommandKind.playEpisode,
      arguments: arguments,
      timeout: null,
      label: 'play "${request.label}"',
    );
  }

  factory EngineCommand.history({bool completed = false, Duration? timeout}) {
    return EngineCommand(
      kind: EngineCommandKind.history,
      arguments: <String>['history', if (completed) 'completed'],
      timeout: timeout ?? const Duration(seconds: 30),
      label: completed ? 'history completed' : 'history',
    );
  }

  factory EngineCommand.historyAdd({
    required String title,
    required String url,
    required String poster,
    required String latestEpisode,
  }) {
    _requireUrl(url, 'url');
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be empty');
    }
    return EngineCommand(
      kind: EngineCommandKind.historyAdd,
      arguments: <String>[
        'history-add',
        title.trim(),
        url,
        poster,
        latestEpisode,
      ],
      timeout: const Duration(seconds: 30),
      label: 'history-add "$title"',
    );
  }

  factory EngineCommand.importHistory(String path) {
    final value = path.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(path, 'path', 'must not be empty');
    }
    return EngineCommand(
      kind: EngineCommandKind.historyImport,
      arguments: <String>['history-import', value],
      timeout: const Duration(seconds: 60),
      label: 'history-import',
    );
  }

  factory EngineCommand.setCompleted(
    String url, {
    required bool completed,
  }) {
    _requireUrl(url, 'url');
    return EngineCommand(
      kind: completed
          ? EngineCommandKind.historyComplete
          : EngineCommandKind.historyUncomplete,
      arguments: <String>[
        completed ? 'history-complete' : 'history-uncomplete',
        url,
      ],
      timeout: const Duration(seconds: 30),
      label: completed ? 'history-complete' : 'history-uncomplete',
    );
  }

  static void _requireUrl(String value, String name) {
    final uri = Uri.tryParse(value);
    // History files created by older engine versions may contain root-relative
    // paths (e.g. "/phim/naruto"). The engine accepts both forms.
    final acceptable = value.startsWith('/') || (uri != null && uri.hasScheme);
    if (!acceptable) {
      throw ArgumentError.value(
          value, name, 'must be an absolute or root-relative URL');
    }
  }

  @override
  String toString() => 'EngineCommand($label)';
}
