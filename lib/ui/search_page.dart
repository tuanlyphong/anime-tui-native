import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../state/browser_controller.dart';
import '../state/playback_controller.dart';
import 'widgets/common.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.browser,
    required this.playback,
    required this.focusNode,
  });

  final BrowserController browser;
  final PlaybackController playback;
  final FocusNode focusNode;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _queryController =
      TextEditingController(text: widget.browser.query);

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _submit() {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;
    unawaited(widget.browser.search(query));
  }

  void _runExample(String query) {
    _queryController.text = query;
    _queryController.selection = TextSelection.collapsed(offset: query.length);
    unawaited(widget.browser.search(query));
  }

  void _openAnime(AnimeSummary anime) {
    unawaited(widget.browser.selectAnime(anime));
  }

  void _play(Episode episode) {
    final anime = widget.browser.selectedAnime;
    if (anime == null) return;
    final playingThis =
        widget.playback.episode?.url == episode.url && widget.playback.isBusy;
    if (playingThis) {
      unawaited(widget.playback.stop());
    } else {
      unawaited(widget.playback.play(anime: anime, episode: episode));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable:
          Listenable.merge(<Listenable>[widget.browser, widget.playback]),
      builder: (context, _) {
        return Column(
          children: [
            _SearchBar(
              controller: _queryController,
              focusNode: widget.focusNode,
              isSearching: widget.browser.isSearching,
              onSubmitted: _submit,
              onClear: () {
                _queryController.clear();
                widget.browser.clearSearch();
              },
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1000;
                  final results = _ResultsPane(
                    browser: widget.browser,
                    onSelect: _openAnime,
                    onExample: _runExample,
                  );
                  final episodes = _EpisodesPane(
                    browser: widget.browser,
                    playback: widget.playback,
                    onPlay: _play,
                    showBack: !wide,
                    onBack: () {
                      widget.browser.clearSelection();
                    },
                  );

                  if (wide) {
                    return Row(
                      children: [
                        Expanded(flex: 5, child: results),
                        const VerticalDivider(width: 1),
                        Expanded(flex: 6, child: episodes),
                      ],
                    );
                  }

                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: widget.browser.selectedAnime != null
                        ? KeyedSubtree(
                            key: const ValueKey<String>('episodes'),
                            child: episodes,
                          )
                        : KeyedSubtree(
                            key: const ValueKey<String>('results'),
                            child: results,
                          ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.isSearching,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSearching;
  final VoidCallback onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSubmitted(),
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Search anime by title…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, child) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: onClear,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: isSearching ? null : onSubmitted,
            icon: isSearching
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search, size: 18),
            label: Text(isSearching ? 'Searching' : 'Search'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsPane extends StatelessWidget {
  const _ResultsPane({
    required this.browser,
    required this.onSelect,
    required this.onExample,
  });

  final BrowserController browser;
  final ValueChanged<AnimeSummary> onSelect;
  final ValueChanged<String> onExample;

  @override
  Widget build(BuildContext context) {
    final error = browser.searchError;
    final results = browser.results;

    return Container(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.35),
      child: Column(
        children: [
          SectionHeader(
            title: 'Search results',
            subtitle: browser.hasSearched
                ? '${results.length} title${results.length == 1 ? '' : 's'} for “${browser.query}”'
                : 'Find a series to start watching',
            actions: [
              if (browser.isSearching)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          Divider(
              height: 1, color: Theme.of(context).colorScheme.outlineVariant),
          Expanded(
            child: switch (true) {
              _ when browser.isSearching && results.isEmpty =>
                const LoadingList(rows: 6),
              _ when error != null => ErrorState(
                  title: 'Search failed',
                  message: error.userMessage,
                  hint: error.hint,
                  details: error.details ?? error.message,
                  onRetry: () => unawaited(browser.search(browser.query)),
                ),
              _ when !browser.hasSearched => _SearchIntro(onExample: onExample),
              _ when results.isEmpty => EmptyState(
                  icon: Icons.search_off,
                  title: 'No matches',
                  message:
                      'Nothing was found for “${browser.query}”. Try a shorter title or a different spelling.',
                ),
              _ => ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: results.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 2),
                  itemBuilder: (context, index) {
                    final anime = results[index];
                    return _AnimeTile(
                      anime: anime,
                      selected: browser.selectedAnime?.url == anime.url,
                      onTap: () => onSelect(anime),
                    );
                  },
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _SearchIntro extends StatelessWidget {
  const _SearchIntro({required this.onExample});

  final ValueChanged<String> onExample;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const examples = <String>['naruto', 'one piece', 'attack on titan'];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.travel_explore,
                size: 42, color: scheme.primary.withValues(alpha: 0.9)),
            const SizedBox(height: 14),
            Text(
              'Search the catalogue',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Type a title above and press Enter. Results load from the '
              'anime-tui engine and are cached locally.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: examples
                  .map((query) => ActionChip(
                        label: Text(query),
                        onPressed: () => onExample(query),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimeTile extends StatelessWidget {
  const _AnimeTile({
    required this.anime,
    required this.selected,
    required this.onTap,
  });

  final AnimeSummary anime;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color:
          selected ? scheme.primary.withValues(alpha: 0.1) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 3,
                color: selected ? scheme.primary : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            children: [
              PosterThumb(url: anime.poster),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anime.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      anime.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodesPane extends StatelessWidget {
  const _EpisodesPane({
    required this.browser,
    required this.playback,
    required this.onPlay,
    required this.showBack,
    required this.onBack,
  });

  final BrowserController browser;
  final PlaybackController playback;
  final ValueChanged<Episode> onPlay;
  final bool showBack;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final anime = browser.selectedAnime;
    if (anime == null) {
      return const EmptyState(
        icon: Icons.subscriptions_outlined,
        title: 'Choose an anime',
        message:
            'Select a title on the left to load its episode list and resume where you left off.',
      );
    }

    final episodes = browser.episodes;
    final preferred =
        episodes.where((episode) => episode.preferred).firstOrNull;
    final error = browser.episodeError;

    return Column(
      children: [
        SectionHeader(
          title: anime.title,
          subtitle: browser.isLoadingEpisodes
              ? 'Loading episodes…'
              : '${episodes.length} episode${episodes.length == 1 ? '' : 's'}',
          actions: [
            if (preferred != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: FilledButton.tonalIcon(
                  onPressed: () => onPlay(preferred),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Resume'),
                ),
              ),
            IconButton(
              tooltip: 'Refresh episodes',
              onPressed: browser.isLoadingEpisodes
                  ? null
                  : () => unawaited(browser.refreshEpisodes()),
              icon: const Icon(Icons.refresh, size: 20),
            ),
            if (showBack)
              IconButton(
                tooltip: 'Back to results',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, size: 20),
              ),
          ],
        ),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        Expanded(
          child: switch (true) {
            _ when browser.isLoadingEpisodes && episodes.isEmpty =>
              const LoadingList(rows: 7, compact: true),
            _ when error != null => ErrorState(
                title: 'Could not load episodes',
                message: error.userMessage,
                hint: error.hint,
                details: error.details ?? error.message,
                onRetry: () => unawaited(browser.refreshEpisodes()),
              ),
            _ when episodes.isEmpty => const EmptyState(
                icon: Icons.video_library_outlined,
                title: 'No episodes found',
                message:
                    'The engine returned an empty episode list. The site may be unavailable or the series may not be published yet.',
              ),
            _ => ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: episodes.length,
                itemBuilder: (context, index) {
                  final episode = episodes[index];
                  final isCurrent =
                      playback.episode?.url == episode.url && playback.isBusy;
                  return _EpisodeTile(
                    episode: episode,
                    isCurrent: isCurrent,
                    onPlay: () => onPlay(episode),
                  );
                },
              ),
          },
        ),
      ],
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.isCurrent,
    required this.onPlay,
  });

  final Episode episode;
  final bool isCurrent;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: isCurrent
          ? scheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? scheme.primary.withValues(alpha: 0.18)
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: isCurrent
                        ? scheme.primary.withValues(alpha: 0.5)
                        : scheme.outlineVariant,
                  ),
                ),
                child: Text(
                  episode.badge,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isCurrent ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      episode.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (episode.hasProgress)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          episode.preferred
                              ? 'Continue from here'
                              : 'Progress saved',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: scheme.primary,
                                  ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isCurrent)
                IconButton(
                  tooltip: 'Stop playback',
                  onPressed: onPlay,
                  icon: Icon(Icons.stop_circle, color: scheme.error, size: 22),
                )
              else
                IconButton(
                  tooltip: 'Play episode',
                  onPressed: onPlay,
                  icon: Icon(Icons.play_circle_outline,
                      color: scheme.primary, size: 24),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
