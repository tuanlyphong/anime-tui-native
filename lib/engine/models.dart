import 'package:flutter/foundation.dart';

@immutable
class AnimeSummary {
  const AnimeSummary({
    required this.title,
    required this.url,
    this.poster = '',
  });

  final String title;
  final String url;
  final String poster;

  bool get isPlayable => title.isNotEmpty && url.isNotEmpty;

  String get subtitle {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    return '${uri.host}${uri.path}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnimeSummary && other.url == url && other.title == title;

  @override
  int get hashCode => Object.hash(url, title);

  @override
  String toString() => 'AnimeSummary($title, $url)';
}

@immutable
class Episode {
  const Episode({
    required this.title,
    required this.url,
    this.originalTitle = '',
    this.preferred = false,
    this.poster = '',
  });

  final String title;
  final String url;

  /// Title without the engine's progress decoration (`· Resume 04:12`).
  final String originalTitle;
  final bool preferred;
  final String poster;

  bool get isPlayable => url.isNotEmpty;

  /// Best-effort episode number used for the compact leading badge.
  String get badge {
    final match = RegExp(
          r'(?:Tập|Episode|Ep)\s*(\d+)',
          caseSensitive: false,
        ).firstMatch(title) ??
        RegExp(r'-\s*(\d+)(?:\.html)?$').firstMatch(url);
    if (match == null) return '•';
    final number = match.group(1)!;
    return number.length > 3 ? number : number.padLeft(2, '0');
  }

  /// True when the engine decorated this row with resume information.
  bool get hasProgress =>
      title.contains('· Resume') || title.contains('Watched');

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Episode && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'Episode($title, $url)';
}

@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.title,
    required this.url,
    required this.poster,
    required this.latestEpisode,
    required this.completed,
  });

  final String title;
  final String url;
  final String poster;
  final String latestEpisode;
  final bool completed;

  AnimeSummary toAnime() =>
      AnimeSummary(title: title, url: url, poster: poster);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HistoryEntry && other.url == url;

  @override
  int get hashCode => url.hashCode;

  /// Convert [this] to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'poster': poster,
        'latestEpisode': latestEpisode,
        'completed': completed,
      };

  /// Create a [HistoryEntry] from a JSON map.
  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      title: json['title'] as String? ?? 'Unknown',
      url: json['url'] as String? ?? '',
      poster: json['poster'] as String? ?? '',
      latestEpisode: json['latestEpisode'] as String? ?? '',
      completed: json['completed'] as bool? ?? false,
    );
  }
}

@immutable
class PlaybackRequest {
  const PlaybackRequest({
    required this.streamUrl,
    required this.animeUrl,
    required this.episodeUrl,
    required this.label,
  });

  final String streamUrl;
  final String animeUrl;
  final String episodeUrl;
  final String label;
}

enum PlaybackOutcome { finished, stopped, failed }

@immutable
class PlaybackResult {
  const PlaybackResult({
    required this.outcome,
    this.error,
    this.statusLines = const <String>[],
  });

  final PlaybackOutcome outcome;
  final String? error;
  final List<String> statusLines;

  bool get isSuccess => outcome == PlaybackOutcome.finished;
}

enum PlaybackStage { preparing, playing }

@immutable
class PlaybackStatus {
  const PlaybackStatus({
    required this.stage,
    required this.text,
    this.percent,
  });

  final PlaybackStage stage;
  final String text;
  final double? percent;
}

@immutable
class EngineHealth {
  const EngineHealth({
    required this.ready,
    required this.message,
    this.nodeVersion,
    this.enginePath = '',
  });

  factory EngineHealth.ready({
    required String nodeVersion,
    required String enginePath,
  }) =>
      EngineHealth(
        ready: true,
        message: 'Engine ready · Node $nodeVersion',
        nodeVersion: nodeVersion,
        enginePath: enginePath,
      );

  factory EngineHealth.unavailable(String message, {String enginePath = ''}) =>
      EngineHealth(ready: false, message: message, enginePath: enginePath);

  final bool ready;
  final String message;
  final String? nodeVersion;
  final String enginePath;
}
