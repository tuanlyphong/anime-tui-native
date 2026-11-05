import 'package:flutter/foundation.dart';

import '../core/errors/engine_exception.dart';
import '../core/logging/app_logger.dart';
import '../engine/engine_client.dart';
import '../engine/models.dart';

/// Owns search and episode-list state for the browser pane.
class BrowserController extends ChangeNotifier {
  BrowserController({
    required AnimeEngine engine,
    required AppLogger logger,
  })  : _engine = engine,
        _logger = logger;

  AnimeEngine _engine;
  final AppLogger _logger;

  String _query = '';
  List<AnimeSummary> _results = <AnimeSummary>[];
  bool _searching = false;
  EngineException? _searchError;
  int _searchGeneration = 0;

  AnimeSummary? _selectedAnime;
  List<Episode> _episodes = <Episode>[];
  bool _loadingEpisodes = false;
  EngineException? _episodeError;
  int _episodeGeneration = 0;

  bool _disposed = false;

  String get query => _query;
  List<AnimeSummary> get results => List<AnimeSummary>.unmodifiable(_results);
  bool get isSearching => _searching;
  EngineException? get searchError => _searchError;
  bool get hasSearched => _query.isNotEmpty;
  AnimeSummary? get selectedAnime => _selectedAnime;
  List<Episode> get episodes => List<Episode>.unmodifiable(_episodes);
  bool get isLoadingEpisodes => _loadingEpisodes;
  EngineException? get episodeError => _episodeError;

  void updateEngine(AnimeEngine engine) {
    _engine = engine;
    _searchGeneration++;
    _episodeGeneration++;
    _results = <AnimeSummary>[];
    _episodes = <Episode>[];
    _selectedAnime = null;
    _searchError = null;
    _episodeError = null;
    _searching = false;
    _loadingEpisodes = false;
    _notify();
  }

  Future<void> search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return;

    final generation = ++_searchGeneration;
    _query = query;
    _searching = true;
    _searchError = null;
    _results = <AnimeSummary>[];
    _selectedAnime = null;
    _episodes = <Episode>[];
    _episodeError = null;
    _notify();

    try {
      final results = await _engine.search(query);
      if (generation != _searchGeneration || _disposed) return;
      _results = results;
      _logger.info('Search state updated', context: {
        'query': query,
        'results': results.length,
      });
    } on Object catch (error, stackTrace) {
      if (generation != _searchGeneration || _disposed) return;
      _searchError = EngineException.from(error, stackTrace: stackTrace);
      _logger.error(
        'Search failed',
        error: error,
        stackTrace: stackTrace,
        context: {'query': query},
      );
    } finally {
      if (generation == _searchGeneration && !_disposed) {
        _searching = false;
        _notify();
      }
    }
  }

  Future<void> selectAnime(
    AnimeSummary anime, {
    String? preferredEpisodeUrl,
  }) async {
    final generation = ++_episodeGeneration;
    _selectedAnime = anime;
    _episodes = <Episode>[];
    _episodeError = null;
    _loadingEpisodes = true;
    _notify();

    try {
      final episodes = await _engine.episodes(
        anime.url,
        preferredEpisodeUrl: preferredEpisodeUrl,
      );
      if (generation != _episodeGeneration || _disposed) return;
      _episodes = episodes;
      _logger.info('Episode state updated', context: {
        'anime': anime.title,
        'episodes': episodes.length,
      });
    } on Object catch (error, stackTrace) {
      if (generation != _episodeGeneration || _disposed) return;
      _episodeError = EngineException.from(error, stackTrace: stackTrace);
      _logger.error(
        'Loading episodes failed',
        error: error,
        stackTrace: stackTrace,
        context: {'anime': anime.url},
      );
    } finally {
      if (generation == _episodeGeneration && !_disposed) {
        _loadingEpisodes = false;
        _notify();
      }
    }
  }

  Future<void> refreshEpisodes() async {
    final anime = _selectedAnime;
    if (anime == null) return;
    await selectAnime(anime);
  }

  void clearSelection() {
    _episodeGeneration++;
    _selectedAnime = null;
    _episodes = <Episode>[];
    _episodeError = null;
    _loadingEpisodes = false;
    _notify();
  }

  void clearSearch() {
    _searchGeneration++;
    _episodeGeneration++;
    _query = '';
    _results = <AnimeSummary>[];
    _searchError = null;
    _searching = false;
    _selectedAnime = null;
    _episodes = <Episode>[];
    _episodeError = null;
    _loadingEpisodes = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
