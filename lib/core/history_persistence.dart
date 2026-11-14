import 'dart:convert';
import 'dart:io';

import '../core/utils/app_paths.dart';
import '../engine/models.dart';

/// Result of merging an imported history file with the local history.
class HistoryImportResult {
  const HistoryImportResult({
    required this.entries,
    required this.imported,
  });

  /// Complete history after the merge.
  final List<HistoryEntry> entries;

  /// Number of valid entries read from the imported file.
  final int imported;
}

/// Saves and loads watch history to/from a local JSON file.
///
/// Merge rule: URLs present in both files use the imported entry (it's the
/// user's latest choice). URLs only in one file are added as-is.
class HistoryPersistence {
  static String get _file => AppPaths.historyFile;

  /// Load history from disk, or return empty if the file doesn't exist.
  static List<HistoryEntry> load({String? filePath}) {
    final file = File(filePath ?? _file);
    if (!file.existsSync()) return const <HistoryEntry>[];
    try {
      final data = file.readAsStringSync();
      final parsed = json.decode(data);
      if (parsed is! List) return const <HistoryEntry>[];
      final result = <HistoryEntry>[];
      for (final item in parsed) {
        if (item is Map<String, dynamic>) {
          try {
            result.add(HistoryEntry.fromJson(item));
          } catch (_) {
            // Skip invalid entries
          }
        }
      }
      return result;
    } on Object {
      return const <HistoryEntry>[];
    }
  }

  /// Save history to disk (atomic write via temp file + rename).
  static Future<bool> save(
    List<HistoryEntry> entries, {
    String? filePath,
  }) async {
    final target = filePath ?? _file;
    final temp = File('$target.tmp');
    try {
      await Directory(File(target).parent.path).create(recursive: true);
      // Write to temp file first.
      await temp.writeAsString(
        json.encode(entries.map((entry) => entry.toJson()).toList()),
        flush: true,
      );
      try {
        // Rename over the existing file (atomic on most platforms).
        await temp.rename(target);
      } on FileSystemException {
        // Windows does not replace an existing target with rename().
        final file = File(target);
        if (await file.exists()) await file.delete();
        await temp.rename(target);
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      // A missing temp file must not turn into a second exception.
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // ignore
      }
    }
  }

  /// Export history as a JSON file to the given path.
  static Future<bool> export(String targetPath,
      {required List<HistoryEntry> entries}) async {
    try {
      final file = File(targetPath);
      final dir = file.parent;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      await file
          .writeAsString(json.encode(entries.map((e) => e.toJson()).toList()));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Import history from a file, merging with existing entries (no conflicts).
  static Future<HistoryImportResult> importAndMerge(String sourcePath) async {
    final file = File(sourcePath);
    if (!file.existsSync()) {
      return HistoryImportResult(entries: load(), imported: 0);
    }
    try {
      return await importAndMergeContent(file.readAsStringSync());
    } catch (_) {
      return HistoryImportResult(entries: load(), imported: 0);
    }
  }

  /// Import history from raw JSON, merging with existing entries.
  static Future<HistoryImportResult> importAndMergeContent(
    String data, {
    String? filePath,
  }) async {
    final existing = load(filePath: filePath);
    final parsed = _decodeHistory(data);
    if (parsed == null) {
      return HistoryImportResult(entries: existing, imported: 0);
    }

    final imported = <HistoryEntry>[];
    for (final item in parsed) {
      if (item is! Map<String, dynamic>) continue;
      try {
        final entry = HistoryEntry.fromJson(item);
        if (entry.url.isEmpty) continue;
        imported.add(entry);
      } catch (_) {
        // Skip invalid entries.
      }
    }

    final merged = <String, HistoryEntry>{};
    for (final entry in existing) {
      if (entry.url.isNotEmpty) merged[entry.url] = entry;
    }
    for (final entry in imported) {
      merged[entry.url] = entry;
    }

    final result = merged.values.toList();
    await save(result, filePath: filePath);
    return HistoryImportResult(entries: result, imported: imported.length);
  }

  static List<dynamic>? _decodeHistory(String data) {
    try {
      final parsed = json.decode(data);
      return parsed is List ? parsed : null;
    } catch (_) {
      return null;
    }
  }
}
