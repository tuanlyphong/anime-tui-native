import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/logging/app_logger.dart';
import 'widgets/common.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key, required this.logger});

  final AppLogger logger;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  LogLevel? _minimumLevel;

  Color _levelColor(LogLevel level, ColorScheme scheme) => switch (level) {
        LogLevel.debug => scheme.onSurfaceVariant,
        LogLevel.info => scheme.primary,
        LogLevel.warning => const Color(0xFFE2B341),
        LogLevel.error => scheme.error,
      };

  Future<void> _copy(List<LogEntry> entries) async {
    final text = entries.map((entry) => entry.toLine()).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${entries.length} log lines')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.logger,
      builder: (context, _) {
        final all = widget.logger.entries;
        final entries = _minimumLevel == null
            ? all
            : all
                .where(
                    (entry) => entry.level.severity >= _minimumLevel!.severity)
                .toList();

        return Column(
          children: [
            SectionHeader(
              title: 'Diagnostics',
              subtitle: widget.logger.filePath ?? 'In-memory log',
              actions: [
                IconButton(
                  tooltip: 'Copy visible logs',
                  onPressed: entries.isEmpty ? null : () => _copy(entries),
                  icon: const Icon(Icons.copy_all, size: 20),
                ),
                IconButton(
                  tooltip: 'Clear logs',
                  onPressed: all.isEmpty ? null : widget.logger.clear,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                ),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _minimumLevel == null,
                    onSelected: () => setState(() => _minimumLevel = null),
                  ),
                  for (final level in LogLevel.values)
                    _FilterChip(
                      label: level.label,
                      selected: _minimumLevel == level,
                      color: _levelColor(level, scheme),
                      onSelected: () => setState(() => _minimumLevel = level),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: entries.isEmpty
                  ? const EmptyState(
                      icon: Icons.terminal,
                      title: 'No log entries',
                      message:
                          'Engine commands, errors, and playback events will appear here.',
                      compact: true,
                    )
                  : SelectionArea(
                      child: ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[entries.length - 1 - index];
                          return _LogRow(
                            entry: entry,
                            color: _levelColor(entry.level, scheme),
                          );
                        },
                      ),
                    ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              child: Text(
                '${entries.length} of ${all.length} entries · newest first',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effective = color ?? scheme.primary;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: selected ? effective : scheme.onSurfaceVariant,
      ),
      backgroundColor: Colors.transparent,
      selectedColor: effective.withValues(alpha: 0.14),
      side: BorderSide(
        color: selected
            ? effective.withValues(alpha: 0.45)
            : scheme.outlineVariant,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry, required this.color});

  final LogEntry entry;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final contextText = entry.context.isEmpty
        ? ''
        : entry.context.entries
            .map((item) => '${item.key}=${item.value}')
            .join('  ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.displayTime,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.45,
            ).copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(
              entry.level.label,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ).copyWith(color: color),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: entry.message),
                  if (contextText.isNotEmpty)
                    TextSpan(
                      text: '  $contextText',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  if (entry.error != null)
                    TextSpan(
                      text: '\n${entry.error}',
                      style: TextStyle(color: scheme.error),
                    ),
                ],
              ),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
