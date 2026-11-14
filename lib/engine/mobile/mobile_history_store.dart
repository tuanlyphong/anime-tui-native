import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/utils/app_paths.dart';
import '../models.dart';

/// JSON-backed watch history for the Android engine.
///
/// The desktop engine owns its own history file; this store is the single
/// source of truth on mobile. It mirrors the desktop sorting rules: series are
/// ordered by episode number, then by the most recent update. Updates for an
/// older episode never move a series backwards.
class MobileHistoryStore {
  MobileHistoryStore({
    String? filePath,
    DateTime Function()? clock,
  })  : _filePath = filePath ?? AppPaths.mobileHistoryFile,
        _clock = clock ?? DateTime.now;

  final String _filePath;
  final DateTime Function() _clock;

  Future<void> _queue = Future<void>.value();

  Future<List<HistoryEntry>> load({required bool completed}) async {
    final records = await _read();
    return records
        .where((record) => record.entry.completed == completed)
        .map((record) => record.entry)
        .toList(growable: false);
  }

  Future<List<HistoryEntry>> loadAll() async {
    final records = await _read();
    return records.map((record) => record.entry).toList(growable: false);
  }

  Future<String?> latestEpisodeFor(String animeUrl) async {
    final path = _pathOf(animeUrl);
    final records = await _read();
    for (final record in records) {
      if (_pathOf(record.entry.url) == path) {
        return record.entry.latestEpisode;
      }
    }
    return null;
  }

  Future<void> add({
    required String title,
    required String url,
    required String poster,
    required String latestEpisode,
  }) {
    return _locked(() async {
      final records = await _read();
      final now = _clock().millisecondsSinceEpoch;
      final index = records.indexWhere(
        (record) => record.entry.url == url,
      );

      if (index < 0) {
        records.add(_Record(
          entry: HistoryEntry(
            title: title,
            url: url,
            poster: poster,
            latestEpisode: latestEpisode,
            completed: false,
          ),
          updated: now,
        ));
      } else {
        final existing = records[index];
        final existingEpisode = _episodeNumber(existing.entry.latestEpisode);
        final nextEpisode = _episodeNumber(latestEpisode);
        final advanced = nextEpisode > existingEpisode ||
            (nextEpisode == existingEpisode && now > existing.updated);
        if (advanced) {
          records[index] = _Record(
            entry: HistoryEntry(
              title: title,
              url: url,
              poster: poster,
              latestEpisode: latestEpisode,
              completed: existing.entry.completed,
            ),
            updated: now,
          );
        }
      }

      records.sort(_compare);
      await _write(records);
    });
  }

  /// Merge imported [entries] into the local store.
  ///
  /// Imported entries replace local records with the same URL, matching the
  /// desktop import semantics (the user's imported copy wins).
  Future<void> merge(List<HistoryEntry> entries) {
    return _locked(() async {
      if (entries.isEmpty) return;
      final records = await _read();
      final byUrl = <String, _Record>{
        for (final record in records) record.entry.url: record,
      };
      final now = _clock().millisecondsSinceEpoch;
      for (final entry in entries) {
        if (entry.url.isEmpty) continue;
        byUrl[entry.url] = _Record(
          entry: HistoryEntry(
            title: entry.title,
            url: entry.url,
            poster: entry.poster,
            latestEpisode: entry.latestEpisode,
            completed: entry.completed,
          ),
          updated: now,
        );
      }
      final merged = byUrl.values.toList()..sort(_compare);
      await _write(merged);
    });
  }

  Future<bool> setCompleted(String url, {required bool completed}) {
    return _locked(() async {
      final records = await _read();
      final index = records.indexWhere((record) => record.entry.url == url);
      if (index < 0) return false;

      final existing = records[index].entry;
      records[index] = _Record(
        entry: HistoryEntry(
          title: existing.title,
          url: existing.url,
          poster: existing.poster,
          latestEpisode: existing.latestEpisode,
          completed: completed,
        ),
        updated: _clock().millisecondsSinceEpoch,
      );
      records.sort(_compare);
      await _write(records);
      return true;
    });
  }

  Future<List<_Record>> _read() async {
    final file = File(_filePath);
    if (!await file.exists()) return <_Record>[];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return <_Record>[];

      final records = <_Record>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          final entry = HistoryEntry.fromJson(
            item.map((key, value) => MapEntry('$key', value)),
          );
          if (entry.url.isEmpty) continue;
          final rawUpdated = item['updated'];
          records.add(_Record(
            entry: entry,
            updated: rawUpdated is num ? rawUpdated.toInt() : 0,
          ));
        } on Object {
          // Skip malformed entries; one bad row must not hide the rest.
        }
      }
      records.sort(_compare);
      return records;
    } on Object {
      return <_Record>[];
    }
  }

  Future<void> _write(List<_Record> records) async {
    final file = File(_filePath);
    final temporary = File('$_filePath.tmp');
    try {
      await file.parent.create(recursive: true);
      await temporary.writeAsString(
        json.encode(records.map((record) => record.toJson()).toList()),
        flush: true,
      );
      try {
        await temporary.rename(_filePath);
      } on FileSystemException {
        if (await file.exists()) await file.delete();
        await temporary.rename(_filePath);
      }
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on Object {
        // Ignore cleanup errors.
      }
    }
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static int _compare(_Record a, _Record b) {
    final byEpisode = _episodeNumber(b.entry.latestEpisode) -
        _episodeNumber(a.entry.latestEpisode);
    if (byEpisode != 0) return byEpisode;
    return b.updated.compareTo(a.updated);
  }

  static int _episodeNumber(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    return match == null ? 0 : int.tryParse(match.group(0)!) ?? 0;
  }

  static String _pathOf(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri != null && uri.hasScheme) {
      return uri.path.endsWith('/') && uri.path.length > 1
          ? uri.path.substring(0, uri.path.length - 1)
          : uri.path;
    }
    return url.trim();
  }
}

class _Record {
  const _Record({required this.entry, required this.updated});

  final HistoryEntry entry;
  final int updated;

  Map<String, Object?> toJson() => <String, Object?>{
        ...entry.toJson(),
        'updated': updated,
      };
}
