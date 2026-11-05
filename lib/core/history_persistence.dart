import 'dart:convert';
import 'dart:io';

import '../core/utils/app_paths.dart';
import '../engine/models.dart';

/// Saves and loads watch history to/from a local JSON file.
///
/// Merge rule: URLs present in both files use the imported entry (it's the
/// user's latest choice). URLs only in one file are added as-is.
class HistoryPersistence {
  static String get _file => AppPaths.historyFile;

  /// Load history from disk, or return empty if the file doesn't exist.
  static List<HistoryEntry> load() {
    final file = File(_file);
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
  static Future<bool> save(List<HistoryEntry> entries) async {
    final dir = Directory(AppPaths.stateDirectory);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final temp = File('$_file.tmp');
    try {
      // Write to temp file first
      await temp.writeAsString(json.encode(entries.map((e) => e.toJson()).toList()));
      // Rename over the existing file (atomic on most platforms)
      await temp.rename(_file);
      return true;
    } catch (e) {
      temp.deleteSync(recursive: true);
      return false;
    }
  }

  /// Export history as a JSON file to the given path.
  static Future<bool> export(String targetPath, {required List<HistoryEntry> entries}) async {
    try {
      final file = File(targetPath);
      final dir = file.parent;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      await file.writeAsString(json.encode(entries.map((e) => e.toJson()).toList()));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Import history from a file, merging with existing entries (no conflicts).
  /// Returns the merged list. Invalid entries are skipped with a warning.
  static List<HistoryEntry> importAndMerge(String sourcePath) {
    final existing = load();
    final file = File(sourcePath);
    if (!file.existsSync()) return existing;

    try {
      final data = file.readAsStringSync();
      final parsed = json.decode(data);
      if (parsed is! List) return existing;

      final imported = <HistoryEntry>[];
      for (final item in parsed) {
        if (item is! Map<String, dynamic>) continue;
        try {
          imported.add(HistoryEntry.fromJson(item));
        } catch (_) {
          // Skip invalid entries
        }
      }

      final merged = <String, HistoryEntry>{};
      for (final entry in existing) {
        if (entry.url.isNotEmpty) {
          merged[entry.url] = entry;
        }
      }
      for (final entry in imported) {
        merged[entry.url] = entry;
      }

      final result = merged.values.toList();
      save(result);
      return result;
    } catch (e) {
      return existing;
    }
  }
}
