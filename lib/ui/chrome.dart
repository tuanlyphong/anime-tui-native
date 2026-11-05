import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../state/browser_controller.dart';
import '../state/playback_controller.dart';
import 'widgets/common.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.index,
    required this.extended,
    required this.onSelect,
    required this.onSettings,
    required this.errorCount,
    required this.engineReady,
  });

  final int index;
  final bool extended;
  final ValueChanged<int> onSelect;
  final VoidCallback onSettings;
  final int errorCount;
  final bool engineReady;

  static const items = <({IconData icon, String label})>[
    (icon: Icons.search, label: 'Search'),
    (icon: Icons.play_circle_outline, label: 'Continue'),
    (icon: Icons.task_alt, label: 'Completed'),
    (icon: Icons.terminal, label: 'Logs'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: extended ? 216 : 74,
      color: scheme.surface.withValues(alpha: 0.45),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              extended ? 18 : 12,
              20,
              extended ? 18 : 12,
              22,
            ),
            child: Row(
              mainAxisAlignment:
                  extended ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.primary,
                        scheme.primary.withValues(alpha: 0.55),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.terminal,
                    size: 21,
                    color: scheme.onPrimary,
                  ),
                ),
                if (extended) ...[
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Anime TUI',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'native desktop',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (var i = 0; i < items.length; i++)
            _SidebarItem(
              icon: items[i].icon,
              label: items[i].label,
              selected: index == i,
              extended: extended,
              badge: i == 3 && errorCount > 0 ? errorCount : null,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment:
                  extended ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: engineReady
                        ? const Color(0xFF55D187)
                        : const Color(0xFFE2B341),
                  ),
                ),
                if (extended) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      engineReady ? 'Engine ready' : 'Setup needed',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          _SidebarItem(
            icon: Icons.settings_outlined,
            label: 'Settings',
            selected: false,
            extended: extended,
            onTap: onSettings,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              extended ? 18 : 0,
              4,
              extended ? 18 : 0,
              14,
            ),
            child: extended
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'v2.0.0',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  )
                : const SizedBox(height: 4),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.extended,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Container(
            height: 42,
            padding: EdgeInsets.symmetric(horizontal: extended ? 12 : 0),
            child: Row(
              mainAxisAlignment:
                  extended ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                if (extended) ...[
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color:
                            selected ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.error.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$badge',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: scheme.error,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (extended) return content;
    return Tooltip(message: label, child: content);
  }
}

class PlaybackBar extends StatelessWidget {
  const PlaybackBar({
    super.key,
    required this.playback,
    required this.onOpenLogs,
  });

  final PlaybackController playback;
  final VoidCallback onOpenLogs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final active = playback.isActive;
        final phase = playback.phase;
        final failed = phase == PlaybackPhase.failed;
        final busy = playback.isBusy;
        final current = switch (phase) {
          PlaybackPhase.resolving => 'Resolving stream',
          PlaybackPhase.starting => 'Starting player',
          PlaybackPhase.playing => 'Playing',
          PlaybackPhase.stopping => 'Stopping',
          PlaybackPhase.finished => 'Finished',
          PlaybackPhase.stopped => 'Stopped',
          PlaybackPhase.failed => 'Failed',
          PlaybackPhase.idle => '',
        };
        final accent = failed
            ? scheme.error
            : phase == PlaybackPhase.finished
                ? const Color(0xFF55D187)
                : scheme.primary;

        return Container(
          height: 74,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              if (active)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    failed
                        ? Icons.error_outline
                        : phase == PlaybackPhase.finished
                            ? Icons.check_circle_outline
                            : Icons.play_circle_fill,
                    color: accent,
                    size: 22,
                  ),
                )
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.movie_outlined,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                    size: 21,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!active)
                      Text(
                        'No active playback',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      )
                    else
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              playback.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusPill(label: current, color: accent),
                        ],
                      ),
                    const SizedBox(height: 4),
                    Text(
                      active
                          ? (playback.error ?? playback.statusText)
                          : 'Select an anime, then press play on an episode.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                failed ? scheme.error : scheme.onSurfaceVariant,
                          ),
                    ),
                    if (busy) ...[
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          minHeight: 2.5,
                          value: playback.progress,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (failed) ...[
                TextButton.icon(
                  onPressed: onOpenLogs,
                  icon: const Icon(Icons.terminal, size: 16),
                  label: const Text('Logs'),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  onPressed: playback.dismiss,
                  icon: const Icon(Icons.close, size: 19),
                ),
              ] else if (busy) ...[
                OutlinedButton.icon(
                  onPressed: () => unawaited(playback.stop()),
                  icon: const Icon(Icons.stop, size: 17),
                  label: const Text('Stop'),
                ),
              ] else if (active) ...[
                IconButton(
                  tooltip: 'Dismiss',
                  onPressed: playback.dismiss,
                  icon: const Icon(Icons.close, size: 19),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class AppStatusBar extends StatelessWidget {
  const AppStatusBar({
    super.key,
    required this.health,
    required this.browser,
    required this.playback,
    required this.onOpenSettings,
  });

  final EngineHealth? health;
  final BrowserController browser;
  final PlaybackController playback;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = health?.ready == true;
    final activity = <String>[
      if (browser.isSearching) 'searching',
      if (browser.isLoadingEpisodes) 'loading episodes',
      if (playback.isBusy) 'playback',
    ];

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.28),
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onOpenSettings,
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ready
                        ? const Color(0xFF55D187)
                        : const Color(0xFFE2B341),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  ready ? 'Engine ready' : 'Engine not ready',
                  style: TextStyle(
                    fontSize: 11,
                    color: ready
                        ? scheme.onSurfaceVariant
                        : const Color(0xFFE2B341),
                  ),
                ),
              ],
            ),
          ),
          if (activity.isNotEmpty) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              activity.join(' · '),
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const Spacer(),
          Text(
            'Ctrl+F search · Ctrl+R refresh · Ctrl+1–4 navigate',
            style: TextStyle(
              fontSize: 10.5,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
