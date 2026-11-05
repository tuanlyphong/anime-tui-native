import 'dart:async';

import 'package:anime_tui_native/engine/engine_client.dart';
import 'package:anime_tui_native/engine/models.dart';

/// In-memory engine used by widget/controller tests.
class FakeEngine implements AnimeEngine {
  FakeEngine({
    List<AnimeSummary>? searchResults,
    Map<String, List<Episode>>? episodesByUrl,
    List<HistoryEntry>? inProgress,
    List<HistoryEntry>? completed,
  })  : searchResults = searchResults ??
            <AnimeSummary>[
              const AnimeSummary(
                title: 'Naruto',
                url: 'https://example.com/phim/naruto',
              ),
              const AnimeSummary(
                title: 'One Piece',
                url: 'https://example.com/phim/one-piece',
              ),
            ],
        episodesByUrl = episodesByUrl ??
            <String, List<Episode>>{
              'https://example.com/phim/naruto': <Episode>[
                const Episode(
                  title: 'Tập 1',
                  url: 'https://example.com/phim/naruto/tap-1.html',
                  preferred: true,
                ),
                const Episode(
                  title: 'Tập 2',
                  url: 'https://example.com/phim/naruto/tap-2.html',
                ),
              ],
            },
        inProgress = inProgress ??
            <HistoryEntry>[
              const HistoryEntry(
                title: 'Naruto',
                url: 'https://example.com/phim/naruto',
                poster: '',
                latestEpisode: 'Tập 1',
                completed: false,
              ),
            ],
        completed = completed ?? <HistoryEntry>[];

  final List<AnimeSummary> searchResults;
  final Map<String, List<Episode>> episodesByUrl;
  final List<HistoryEntry> inProgress;
  final List<HistoryEntry> completed;

  final List<String> calls = <String>[];
  final List<PlaybackRequest> playRequests = <PlaybackRequest>[];
  final List<Map<String, String>> historyAdds = <Map<String, String>>[];
  final Map<String, bool> completionCalls = <String, bool>{};

  Future<List<AnimeSummary>> Function(String query)? onSearch;
  Object? searchError;
  Object? episodesError;
  Object? streamError;
  Object? historyError;

  String streamUrl = 'https://cdn.example.com/episode.mp4';
  PlaybackResult playbackResult =
      const PlaybackResult(outcome: PlaybackOutcome.finished);
  List<PlaybackStatus> playbackStatuses = const <PlaybackStatus>[
    PlaybackStatus(
      stage: PlaybackStage.playing,
      text: 'Playing Naruto 25% · 05:00 / 20:00',
      percent: 0.25,
    ),
  ];

  /// When set, playback waits for this before completing.
  Completer<void>? playbackGate;

  /// When set, stream resolution waits for this before returning.
  Completer<void>? streamGate;

  /// When set, history reads wait for this before returning.
  Completer<void>? historyGate;

  bool disposed = false;

  @override
  Future<List<AnimeSummary>> search(String query) async {
    calls.add('search:$query');
    if (searchError != null) throw searchError!;
    if (onSearch != null) return onSearch!(query);
    return searchResults;
  }

  @override
  Future<List<Episode>> episodes(
    String animeUrl, {
    String? preferredEpisodeUrl,
  }) async {
    calls.add('episodes:$animeUrl');
    if (episodesError != null) throw episodesError!;
    return episodesByUrl[animeUrl] ?? const <Episode>[];
  }

  @override
  Future<String> resolveStream(String episodeUrl) async {
    calls.add('streams:$episodeUrl');
    if (streamError != null) throw streamError!;
    final gate = streamGate;
    if (gate != null) await gate.future;
    return streamUrl;
  }

  @override
  Future<PlaybackSession> play(PlaybackRequest request) async {
    calls.add('play');
    playRequests.add(request);
    final statuses = StreamController<PlaybackStatus>();
    final completer = Completer<PlaybackResult>();
    var stopped = false;

    scheduleMicrotask(() async {
      for (final status in playbackStatuses) {
        if (!statuses.isClosed) statuses.add(status);
      }
      final gate = playbackGate;
      if (gate != null) await gate.future;
      if (!completer.isCompleted) {
        completer.complete(
          stopped
              ? const PlaybackResult(outcome: PlaybackOutcome.stopped)
              : playbackResult,
        );
      }
      if (!statuses.isClosed) await statuses.close();
    });

    return PlaybackSession(
      statuses: statuses.stream,
      result: completer.future,
      stop: () async {
        stopped = true;
        if (!completer.isCompleted) {
          completer.complete(
            const PlaybackResult(outcome: PlaybackOutcome.stopped),
          );
        }
        if (!statuses.isClosed) await statuses.close();
      },
    );
  }

  @override
  Future<List<HistoryEntry>> history({required bool completed}) async {
    calls.add('history:$completed');
    if (historyError != null) throw historyError!;
    final gate = historyGate;
    if (gate != null) await gate.future;
    return completed ? this.completed : inProgress;
  }

  @override
  Future<void> addHistory({
    required String title,
    required String url,
    required String poster,
    required String latestEpisode,
  }) async {
    calls.add('history-add');
    historyAdds.add(<String, String>{
      'title': title,
      'url': url,
      'poster': poster,
      'latestEpisode': latestEpisode,
    });
  }

  @override
  Future<void> setCompleted(String url, {required bool completed}) async {
    calls.add('set-completed:$completed');
    completionCalls[url] = completed;
    final inProgressIndex = inProgress.indexWhere((entry) => entry.url == url);
    final completedIndex =
        this.completed.indexWhere((entry) => entry.url == url);
    final source = inProgressIndex >= 0 ? inProgress : this.completed;
    final index = inProgressIndex >= 0 ? inProgressIndex : completedIndex;
    final target = completed ? this.completed : inProgress;
    if (index >= 0) {
      final entry = source.removeAt(index);
      target.add(HistoryEntry(
        title: entry.title,
        url: entry.url,
        poster: entry.poster,
        latestEpisode: entry.latestEpisode,
        completed: completed,
      ));
    }
  }

  @override
  Future<EngineHealth> checkHealth() async {
    return EngineHealth.ready(
      nodeVersion: 'v20.11.0',
      enginePath: '/tmp/anime.js',
    );
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
