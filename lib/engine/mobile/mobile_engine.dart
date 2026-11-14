import '../../core/errors/engine_exception.dart';
import '../../core/logging/app_logger.dart';
import '../engine_client.dart';
import '../models.dart';
import 'mobile_history_store.dart';
import 'mobile_parsers.dart';
import 'mobile_site_gateway.dart';
import 'mobile_webview_browser.dart';

/// Search backend used by [MobileEngine]; the gateway talks plain HTTP.
abstract interface class MobileSearchSource {
  Future<List<AnimeSummary>> search(String query);
}

/// Headless browser backend used for episode pages and stream resolution.
abstract interface class MobilePageBrowser {
  Future<List<Object?>> fetchEpisodeRows(String animeUrl);

  Future<String> resolvePlayer(String episodeUrl);

  Future<void> dispose();
}

/// Android implementation of [AnimeEngine].
///
/// Search uses the site's JSON/HTML endpoint over HTTP. Episode and stream
/// pages sit behind Cloudflare and require a real WebView, so those operations
/// are delegated to a headless browser. Playback is intentionally not handled
/// here: the UI owns a full-screen WebView session.
class MobileEngine implements AnimeEngine {
  MobileEngine({
    MobileSearchSource? searchSource,
    MobilePageBrowser? browser,
    MobileHistoryStore? history,
    AppLogger? logger,
  })  : _logger = logger ?? AppLogger.instance,
        _searchSource = searchSource ?? MobileSiteGateway(),
        _browser = browser ?? MobileWebViewBrowser(logger: logger),
        _history = history ?? MobileHistoryStore();

  final MobileSearchSource _searchSource;
  final MobilePageBrowser _browser;
  final MobileHistoryStore _history;
  final AppLogger _logger;

  @override
  Future<List<AnimeSummary>> search(String query) async {
    final value = query.trim();
    if (value.isEmpty) return const <AnimeSummary>[];
    final results = await _searchSource.search(value);
    _logger.info('Mobile search completed', context: {
      'query': value,
      'results': results.length,
    });
    return results;
  }

  @override
  Future<List<Episode>> episodes(
    String animeUrl, {
    String? preferredEpisodeUrl,
  }) async {
    final rows = await _browser.fetchEpisodeRows(animeUrl);
    final latest =
        preferredEpisodeUrl == null || preferredEpisodeUrl.trim().isEmpty
            ? await _history.latestEpisodeFor(animeUrl)
            : null;
    final episodes = parseMobileEpisodes(
      rows,
      preferredEpisodeUrl: preferredEpisodeUrl,
      latestEpisode: latest,
    );
    _logger.info('Mobile episodes loaded', context: {
      'url': animeUrl,
      'episodes': episodes.length,
    });
    return episodes;
  }

  @override
  Future<String> resolveStream(String episodeUrl) async {
    final url = await _browser.resolvePlayer(episodeUrl);
    _logger.info('Mobile stream resolved', context: {
      'episode': episodeUrl,
      'host': Uri.parse(url).host,
    });
    return url;
  }

  @override
  Future<PlaybackSession> play(PlaybackRequest request) {
    throw EngineException(
      EngineErrorKind.unsupportedPlatform,
      'Mobile playback is handled by the in-app WebView player.',
    );
  }

  @override
  Future<List<HistoryEntry>> history({required bool completed}) =>
      _history.load(completed: completed);

  @override
  Future<void> addHistory({
    required String title,
    required String url,
    required String poster,
    required String latestEpisode,
  }) =>
      _history.add(
        title: title,
        url: url,
        poster: poster,
        latestEpisode: latestEpisode,
      );

  @override
  Future<void> setCompleted(String url, {required bool completed}) async {
    await _history.setCompleted(url, completed: completed);
  }

  @override
  Future<void> importHistory(List<HistoryEntry> entries) =>
      _history.merge(entries);

  @override
  Future<EngineHealth> checkHealth() async => const EngineHealth(
        ready: true,
        message: 'Mobile engine ready · in-app WebView',
        enginePath: 'built-in',
      );

  @override
  Future<void> dispose() => _browser.dispose();
}
