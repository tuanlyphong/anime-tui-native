import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_scope.dart';
import '../core/logging/app_logger.dart';
import '../engine/models.dart';
import '../state/app_controller.dart';
import '../state/playback_controller.dart';
import 'chrome.dart';
import 'history_page.dart';
import 'logs_page.dart';
import 'mobile_info_dialog.dart';
import 'mobile_player_page.dart';
import 'search_page.dart';
import 'settings_dialog.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const double _mobileBreakpoint = 900;

  int _index = 0;
  final FocusNode _searchFocus = FocusNode(debugLabel: 'search-field');
  PlaybackController? _wiredPlayback;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!Platform.isAndroid || _wiredPlayback != null) return;

    final controller = AppScope.of(context);
    _wiredPlayback = controller.playback;
    controller.playback.sessionFactory = (request) async {
      return openMobilePlaybackSession(
        context,
        request,
        logger: controller.logger,
      );
    };
  }

  @override
  void dispose() {
    if (_wiredPlayback != null) _wiredPlayback!.sessionFactory = null;
    _searchFocus.dispose();
    super.dispose();
  }

  bool get _isWide => MediaQuery.sizeOf(context).width >= _mobileBreakpoint;

  void _select(int index, AppController controller) {
    if (_index == index) return;
    setState(() => _index = index);
    if (index == 0 && _isWide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  void _focusSearch() {
    if (_index != 0) setState(() => _index = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _openAnime(AnimeSummary anime, AppController controller) {
    setState(() => _index = 0);
    unawaited(controller.browser.selectAnime(anime));
  }

  void _refresh(AppController controller) {
    if (_index == 0) {
      if (controller.browser.selectedAnime != null) {
        unawaited(controller.browser.refreshEpisodes());
      } else if (controller.browser.query.isNotEmpty) {
        unawaited(controller.browser.search(controller.browser.query));
      } else {
        unawaited(controller.refreshHealth());
      }
    } else if (_index == 1) {
      unawaited(controller.history.load(completed: false, force: true));
    } else if (_index == 2) {
      unawaited(controller.history.load(completed: true, force: true));
    } else {
      unawaited(controller.refreshHealth());
    }
  }

  Future<void> _openSettings(AppController controller) {
    if (Platform.isAndroid) {
      return showMobileInfoDialog(context, controller);
    }
    return showSettingsDialog(context, controller);
  }

  void _handleBack(AppController controller) {
    if (controller.browser.selectedAnime != null) {
      controller.browser.clearSelection();
      return;
    }
    if (_index != 0) {
      setState(() => _index = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final wide = _isWide;
        final errorCount = controller.logger.entries
            .where((entry) => entry.level == LogLevel.error)
            .length;

        return PopScope(
          canPop:
              wide || (_index == 0 && controller.browser.selectedAnime == null),
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _handleBack(controller);
          },
          child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                  _focusSearch,
              const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                  _focusSearch,
              const SingleActivator(LogicalKeyboardKey.keyR, control: true):
                  () => _refresh(controller),
              const SingleActivator(LogicalKeyboardKey.digit1, control: true):
                  () => _select(0, controller),
              const SingleActivator(LogicalKeyboardKey.digit2, control: true):
                  () => _select(1, controller),
              const SingleActivator(LogicalKeyboardKey.digit3, control: true):
                  () => _select(2, controller),
              const SingleActivator(LogicalKeyboardKey.digit4, control: true):
                  () => _select(3, controller),
              const SingleActivator(LogicalKeyboardKey.comma, control: true):
                  () => unawaited(_openSettings(controller)),
            },
            child: Focus(
              autofocus: wide,
              child: wide
                  ? _buildDesktop(controller, errorCount)
                  : _buildMobile(controller),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktop(AppController controller, int errorCount) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                AppSidebar(
                  index: _index,
                  extended: MediaQuery.sizeOf(context).width >= 1050,
                  onSelect: (index) => _select(index, controller),
                  onSettings: () => unawaited(_openSettings(controller)),
                  errorCount: errorCount,
                  engineReady: controller.health?.ready == true,
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      if (controller.isInitializing)
                        const LinearProgressIndicator(minHeight: 2),
                      if (!controller.isInitializing &&
                          controller.health?.ready != true)
                        _EngineBanner(
                          health: controller.health,
                          startupError: controller.startupError,
                          onSettings: () =>
                              unawaited(_openSettings(controller)),
                        ),
                      Expanded(child: _pages(controller)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          PlaybackBar(
            playback: controller.playback,
            onOpenLogs: () => _select(3, controller),
          ),
          AppStatusBar(
            health: controller.health,
            browser: controller.browser,
            playback: controller.playback,
            onOpenSettings: () => unawaited(_openSettings(controller)),
          ),
        ],
      ),
    );
  }

  Widget _buildMobile(AppController controller) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.55),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.terminal,
                size: 17,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Anime TUI'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _refresh(controller),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'About and storage',
            onPressed: () => unawaited(_openSettings(controller)),
            icon: const Icon(Icons.info_outline),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (controller.isInitializing)
            const LinearProgressIndicator(minHeight: 2),
          if (!controller.isInitializing && controller.health?.ready != true)
            _EngineBanner(
              health: controller.health,
              startupError: controller.startupError,
              onSettings: () => unawaited(_openSettings(controller)),
            ),
          Expanded(child: _pages(controller)),
          ListenableBuilder(
            listenable: controller.playback,
            builder: (context, _) => controller.playback.isActive
                ? PlaybackBar(
                    playback: controller.playback,
                    onOpenLogs: () => _select(3, controller),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => _select(index, controller),
        destinations: [
          for (final item in AppSidebar.items)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.icon),
              label: item.label,
            ),
        ],
      ),
    );
  }

  Widget _pages(AppController controller) {
    return IndexedStack(
      index: _index,
      children: [
        SearchPage(
          browser: controller.browser,
          playback: controller.playback,
          focusNode: _searchFocus,
        ),
        HistoryPage(
          history: controller.history,
          completed: false,
          active: _index == 1,
          onOpenAnime: (anime) => _openAnime(anime, controller),
        ),
        HistoryPage(
          key: const ValueKey<String>('completed-history'),
          history: controller.history,
          completed: true,
          active: _index == 2,
          onOpenAnime: (anime) => _openAnime(anime, controller),
        ),
        LogsPage(logger: controller.logger),
      ],
    );
  }
}

class _EngineBanner extends StatelessWidget {
  const _EngineBanner({
    required this.health,
    required this.startupError,
    required this.onSettings,
  });

  final EngineHealth? health;
  final String? startupError;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final warning = const Color(0xFFE2B341);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 9, 12, 9),
      color: warning.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(Icons.link_off, size: 17, color: warning),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              startupError ??
                  health?.message ??
                  'The engine is not configured. Set the anime.js path to start.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurface),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onSettings,
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }
}
