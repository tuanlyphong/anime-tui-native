import 'package:flutter/material.dart';

import '../core/utils/app_paths.dart';
import '../state/app_controller.dart';

/// Mobile replacement for the desktop engine-settings dialog.
Future<void> showMobileInfoDialog(
  BuildContext context,
  AppController controller,
) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return AlertDialog(
        title: const Text('Anime TUI for Android'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                controller.health?.message ??
                    'The mobile engine is built into the app.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Text(
                'Search uses the site API. Episodes and video playback run in '
                'the built-in WebView, so Node.js, Java, mpv, and Playwright '
                'are not required on this device.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              _PathRow(
                label: 'History',
                value: AppPaths.mobileHistoryFile,
              ),
              const SizedBox(height: 10),
              _PathRow(
                label: 'Logs',
                value: AppPaths.logFile,
              ),
              const SizedBox(height: 18),
              Text(
                'v2.0.0 · sideload build',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

class _PathRow extends StatelessWidget {
  const _PathRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
