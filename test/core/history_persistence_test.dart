import 'dart:convert';
import 'dart:io';

import 'package:anime_tui_native/core/history_persistence.dart';
import 'package:anime_tui_native/engine/models.dart';
import 'package:flutter_test/flutter_test.dart';

const HistoryEntry _oldEntry = HistoryEntry(
  title: 'Old title',
  url: 'https://example.test/phim/old',
  poster: '',
  latestEpisode: 'Tập 1',
  completed: false,
);

void main() {
  late Directory directory;
  late String path;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('anime-history-test-');
    path = '${directory.path}/history.json';
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('merges imported entries by URL and persists the result', () async {
    await HistoryPersistence.save(<HistoryEntry>[_oldEntry], filePath: path);

    final result = await HistoryPersistence.importAndMergeContent(
      jsonEncode(<Object?>[
        <String, Object?>{
          'title': 'Old title updated',
          'url': 'https://example.test/phim/old',
          'poster': 'https://cdn.test/old.jpg',
          'latestEpisode': 'Tập 2',
          'completed': true,
        },
        <String, Object?>{
          'title': 'New title',
          'url': 'https://example.test/phim/new',
          'poster': '',
          'latestEpisode': 'Tập 1',
          'completed': false,
        },
        <String, Object?>{
          'title': 'No URL',
          'url': '',
        },
        'not a map',
      ]),
      filePath: path,
    );

    expect(result.imported, 2);
    expect(result.entries, hasLength(2));
    final old = result.entries.singleWhere(
      (entry) => entry.url.endsWith('/old'),
    );
    expect(old.title, 'Old title updated');
    expect(old.latestEpisode, 'Tập 2');
    expect(old.completed, isTrue);

    final reloaded = HistoryPersistence.load(filePath: path);
    expect(reloaded, hasLength(2));
  });

  test('invalid JSON leaves existing history untouched', () async {
    await HistoryPersistence.save(<HistoryEntry>[_oldEntry], filePath: path);

    final result = await HistoryPersistence.importAndMergeContent(
      'not json',
      filePath: path,
    );

    expect(result.imported, 0);
    expect(result.entries, hasLength(1));
    expect(result.entries.single.title, _oldEntry.title);
  });

  test('a JSON object is not accepted as a history list', () async {
    final result = await HistoryPersistence.importAndMergeContent(
      jsonEncode(<String, Object?>{'title': 'Naruto'}),
      filePath: path,
    );

    expect(result.imported, 0);
    expect(result.entries, isEmpty);
  });
}
