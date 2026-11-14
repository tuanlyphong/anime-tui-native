import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/errors/engine_exception.dart';
import '../core/history_persistence.dart';
import '../core/logging/app_logger.dart';
import '../engine/engine_client.dart';
import '../engine/models.dart';

/// Caches the two history lists (in progress and completed) and handles
/// mark-complete actions.
class HistoryController extends ChangeNotifier {
  HistoryController({
    required AnimeEngine engine,
    required AppLogger logger,
  })  : _engine = engine,
        _logger = logger;

  AnimeEngine _engine;
  final AppLogger _logger;

  final Map<bool, List<HistoryEntry>> _entries = <bool, List<HistoryEntry>>{};
  final Map<bool, bool> _loading = <bool, bool>{};
  final Map<bool, EngineException?> _errors = <bool, EngineException?>{};
  final Map<bool, int> _loadGenerations = <bool, int>{};
  final Set<String> _busyUrls = <String>{};

  /// Bumped whenever the engine changes so results from an in-flight request
  /// against the previous engine are discarded.
  int _epoch = 0;
  bool _disposed = false;

  void updateEngine(AnimeEngine engine) {
    _engine = engine;
    _epoch++;
    _entries.clear();
    _loading.clear();
    _errors.clear();
    _busyUrls.clear();
    _notify();
  }

  List<HistoryEntry> entries({required bool completed}) =>
      List<HistoryEntry>.unmodifiable(
        _entries[completed] ?? const <HistoryEntry>[],
      );

  bool isLoading({required bool completed}) => _loading[completed] ?? false;

  EngineException? error({required bool completed}) => _errors[completed];

  bool isBusy(String url) => _busyUrls.contains(url);

  bool hasLoaded({required bool completed}) => _entries.containsKey(completed);

  Future<void> load({required bool completed, bool force = false}) async {
    if (!force &&
        (isLoading(completed: completed) || hasLoaded(completed: completed))) {
      return;
    }

    final epoch = _epoch;
    final generation = (_loadGenerations[completed] ?? 0) + 1;
    _loadGenerations[completed] = generation;
    _loading[completed] = true;
    _errors[completed] = null;
    _notify();

    bool isCurrent() =>
        !_disposed &&
        epoch == _epoch &&
        generation == _loadGenerations[completed];

    try {
      final entries = await _engine.history(completed: completed);
      if (!isCurrent()) return;
      _entries[completed] = entries;
      _logger.info('History state updated', context: {
        'completed': completed,
        'entries': entries.length,
      });
    } on Object catch (error, stackTrace) {
      if (!isCurrent()) return;
      _errors[completed] = EngineException.from(error, stackTrace: stackTrace);
      _logger.error(
        'Loading history failed',
        error: error,
        stackTrace: stackTrace,
        context: {'completed': completed},
      );
    } finally {
      if (isCurrent()) {
        _loading[completed] = false;
        _notify();
      }
    }
  }

  Future<void> setCompleted(
    HistoryEntry entry, {
    required bool completed,
  }) async {
    if (_busyUrls.contains(entry.url)) return;
    _busyUrls.add(entry.url);
    _notify();
    try {
      await _engine.setCompleted(entry.url, completed: completed);
      _logger.info('History entry updated', context: {
        'url': entry.url,
        'completed': completed,
      });
      _busyUrls.remove(entry.url);
      // Refresh both lists: the entry moves between tabs.
      await load(completed: false, force: true);
      await load(completed: true, force: true);
      // Persist to disk.
      await persist();
    } on Object catch (error, stackTrace) {
      _busyUrls.remove(entry.url);
      _errors[completed] = EngineException.from(error, stackTrace: stackTrace);
      _logger.error(
        'Updating history failed',
        error: error,
        stackTrace: stackTrace,
        context: {'url': entry.url},
      );
      _notify();
    }
  }

  /// Save history to disk (called after changes).
  Future<void> persist() async {
    final all = <HistoryEntry>[];
    for (final entries in _entries.values) {
      all.addAll(entries);
    }
    await HistoryPersistence.save(all);
  }

  /// Export history to a file (user can share it with another device).
  Future<bool> exportHistory(String path) async {
    final all = <HistoryEntry>[];
    for (final entries in _entries.values) {
      all.addAll(entries);
    }
    return HistoryPersistence.export(path, entries: all);
  }

  /// Import history from raw JSON, merging with existing entries.
  ///
  /// The merge goes through the active engine so it lands in the store the
  /// engine actually reads on the next launch (`mobile-history.json` on
  /// Android, the engine's own history file on desktop).
  Future<({int imported, int total})> importHistoryContent(String data) async {
    final entries = _parseEntries(data);
    if (entries.isEmpty) {
      return (imported: 0, total: _entryCount());
    }
    await _engine.importHistory(entries);
    await load(completed: false, force: true);
    await load(completed: true, force: true);
    return (imported: entries.length, total: _entryCount());
  }

  /// Import history from a file path, merging with existing entries.
  Future<({int imported, int total})> importHistory(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      return (imported: 0, total: _entryCount());
    }
    try {
      return await importHistoryContent(await file.readAsString());
    } on Object catch (error, stackTrace) {
      _logger.error(
        'Importing history failed',
        error: error,
        stackTrace: stackTrace,
      );
      return (imported: 0, total: _entryCount());
    }
  }

  List<HistoryEntry> _parseEntries(String data) {
    Object? parsed;
    try {
      parsed = jsonDecode(data);
    } on FormatException {
      return const <HistoryEntry>[];
    }
    if (parsed is! List) return const <HistoryEntry>[];

    final entries = <HistoryEntry>[];
    for (final item in parsed) {
      if (item is! Map) continue;
      try {
        final entry = HistoryEntry.fromJson(
          item.map((key, value) => MapEntry('$key', value)),
        );
        if (entry.url.isEmpty) continue;
        entries.add(entry);
      } on Object {
        // Skip malformed entries; one bad row must not reject the file.
      }
    }
    return entries;
  }

  int _entryCount() =>
      _entries.values.fold(0, (total, entries) => total + entries.length);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
