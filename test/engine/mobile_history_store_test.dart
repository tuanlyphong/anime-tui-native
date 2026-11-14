import 'dart:io';

import 'package:anime_tui_native/engine/mobile/mobile_history_store.dart';
import 'package:anime_tui_native/engine/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late MobileHistoryStore store;
  var now = DateTime.utc(2026, 1, 1, 12);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anime-tui-mobile');
    now = DateTime.utc(2026, 1, 1, 12);
    store = MobileHistoryStore(
      filePath: '${directory.path}/mobile-history.json',
      clock: () => now,
    );
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('adds a new series to the in-progress list', () async {
    await store.add(
      title: 'Naruto',
      url: 'https://live.test/phim/naruto',
      poster: 'https://cdn.test/naruto.jpg',
      latestEpisode: 'Tập 1',
    );

    final inProgress = await store.load(completed: false);
    expect(inProgress, hasLength(1));
    expect(inProgress.single.title, 'Naruto');
    expect(inProgress.single.latestEpisode, 'Tập 1');
    expect(await store.load(completed: true), isEmpty);
  });

  test('only advances to a newer episode number', () async {
    await store.add(
      title: 'Naruto',
      url: 'https://live.test/phim/naruto',
      poster: '',
      latestEpisode: 'Tập 3',
    );

    now = now.add(const Duration(minutes: 1));
    await store.add(
      title: 'Naruto',
      url: 'https://live.test/phim/naruto',
      poster: '',
      latestEpisode: 'Tập 2',
    );

    var entries = await store.load(completed: false);
    expect(entries.single.latestEpisode, 'Tập 3');

    now = now.add(const Duration(minutes: 1));
    await store.add(
      title: 'Naruto',
      url: 'https://live.test/phim/naruto',
      poster: '',
      latestEpisode: 'Tập 10',
    );

    entries = await store.load(completed: false);
    expect(entries.single.latestEpisode, 'Tập 10');
  });

  test('sorts series by episode number and then by update time', () async {
    await store.add(
      title: 'Naruto',
      url: 'https://live.test/phim/naruto',
      poster: '',
      latestEpisode: 'Tập 2',
    );
    now = now.add(const Duration(minutes: 1));
    await store.add(
      title: 'One Piece',
      url: 'https://live.test/phim/one-piece',
      poster: '',
      latestEpisode: 'Tập 10',
    );

    final entries = await store.load(completed: false);
    expect(
        entries.map((entry) => entry.title), <String>['One Piece', 'Naruto']);
  });

  test('completed entries move lists and survive later progress', () async {
    await store.add(
      title: 'Naruto',
      url: 'https://live.test/phim/naruto',
      poster: '',
      latestEpisode: 'Tập 1',
    );
    await store.setCompleted(
      'https://live.test/phim/naruto',
      completed: true,
    );

    expect(await store.load(completed: false), isEmpty);
    expect(await store.load(completed: true), hasLength(1));

    now = now.add(const Duration(minutes: 1));
    await store.add(
      title: 'Naruto',
      url: 'https://live.test/phim/naruto',
      poster: '',
      latestEpisode: 'Tập 2',
    );

    expect(await store.load(completed: false), isEmpty);
    final completed = await store.load(completed: true);
    expect(completed.single.latestEpisode, 'Tập 2');
    expect(completed.single.completed, isTrue);
  });

  test('returns the latest episode title for a series', () async {
    await store.add(
      title: 'Naruto',
      url: 'https://live.test/phim/naruto',
      poster: '',
      latestEpisode: 'Tập 4',
    );
    await store.add(
      title: 'One Piece',
      url: 'https://live.test/phim/one-piece',
      poster: '',
      latestEpisode: 'Tập 100',
    );

    expect(
      await store.latestEpisodeFor('https://live.test/phim/naruto'),
      'Tập 4',
    );
    expect(
      await store.latestEpisodeFor('https://live.test/phim/unknown'),
      isNull,
    );
  });

  test('ignores a corrupt history file instead of crashing', () async {
    await File('${directory.path}/mobile-history.json')
        .writeAsString('{not json');

    expect(await store.load(completed: false), isEmpty);
  });

  test('merges imported history and survives a reload', () async {
    await store.add(
      title: 'Naruto',
      url: 'https://live.test/phim/naruto',
      poster: '',
      latestEpisode: 'Tập 5',
    );

    await store.merge(const <HistoryEntry>[
      HistoryEntry(
        title: 'One Piece',
        url: 'https://live.test/phim/one-piece',
        poster: '',
        latestEpisode: 'Tập 100',
        completed: false,
      ),
      HistoryEntry(
        title: 'Naruto',
        url: 'https://live.test/phim/naruto',
        poster: '',
        latestEpisode: 'Tập 7',
        completed: true,
      ),
    ]);

    final reloaded = MobileHistoryStore(
      filePath: '${directory.path}/mobile-history.json',
      clock: () => now,
    );

    final inProgress = await reloaded.load(completed: false);
    expect(
      inProgress.map((entry) => entry.title),
      <String>['One Piece'],
    );
    final completed = await reloaded.load(completed: true);
    expect(completed.single.title, 'Naruto');
    expect(completed.single.latestEpisode, 'Tập 7');
    expect(completed.single.completed, isTrue);
  });
}
