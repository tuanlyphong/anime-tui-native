import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/history_export.dart';
import '../engine/models.dart';
import '../state/history_controller.dart';
import 'widgets/common.dart';

enum _ExportAction { save, share }

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.history,
    required this.completed,
    required this.active,
    required this.onOpenAnime,
  });

  final HistoryController history;
  final bool completed;
  final bool active;
  final ValueChanged<AnimeSummary> onOpenAnime;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  @override
  void initState() {
    super.initState();
    if (widget.active) _scheduleLoad();
  }

  @override
  void didUpdateWidget(HistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _scheduleLoad();
  }

  void _scheduleLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(widget.history.load(completed: widget.completed));
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.history,
      builder: (context, _) {
        final entries = widget.history.entries(completed: widget.completed);
        final loading = widget.history.isLoading(completed: widget.completed);
        final error = widget.history.error(completed: widget.completed);

        return Column(
          children: [
            SectionHeader(
              title: widget.completed ? 'Completed' : 'Continue watching',
              subtitle: loading
                  ? 'Loading history…'
                  : '${entries.length} title${entries.length == 1 ? '' : 's'}',
              actions: [
                IconButton(
                  tooltip: 'Refresh history',
                  onPressed: loading
                      ? null
                      : () => unawaited(widget.history.load(
                            completed: widget.completed,
                            force: true,
                          )),
                  icon: const Icon(Icons.refresh, size: 20),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Export history (manual)',
                  onPressed: () => _export(context),
                  icon: const Icon(Icons.cloud_download, size: 20),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Import history (manual)',
                  onPressed: () => _import(context),
                  icon: const Icon(Icons.cloud_upload, size: 20),
                ),
              ],
            ),
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              child: switch (true) {
                _ when loading && entries.isEmpty => const LoadingList(rows: 5),
                _ when error != null => ErrorState(
                    title: 'Could not load history',
                    message: error.userMessage,
                    hint: error.hint,
                    details: error.details ?? error.message,
                    onRetry: () => unawaited(widget.history.load(
                      completed: widget.completed,
                      force: true,
                    )),
                  ),
                _ when entries.isEmpty => EmptyState(
                    icon: widget.completed
                        ? Icons.task_alt
                        : Icons.history_toggle_off,
                    title: widget.completed
                        ? 'Nothing completed yet'
                        : 'No watch history',
                    message: widget.completed
                        ? 'Series you mark as completed will be archived here.'
                        : 'Start an episode and it will appear here with its latest progress.',
                  ),
                _ => ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: entries.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 2),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _HistoryTile(
                        entry: entry,
                        busy: widget.history.isBusy(entry.url),
                        onOpen: () => widget.onOpenAnime(entry.toAnime()),
                        onToggleCompleted: () => unawaited(
                          widget.history.setCompleted(
                            entry,
                            completed: !entry.completed,
                          ),
                        ),
                      );
                    },
                  ),
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _export(BuildContext context) async {
    final action = await showDialog<_ExportAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export history'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Save the history file to a folder on this device, or share it '
              'with another app.',
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Save to folder'),
              subtitle: const Text('Choose a folder and file name'),
              onTap: () => Navigator.of(context).pop(_ExportAction.save),
            ),
            if (Platform.isAndroid)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share with apps'),
                subtitle: const Text('Gmail, Messenger, Drive, and more'),
                onTap: () => Navigator.of(context).pop(_ExportAction.share),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return;

    String data;
    try {
      data = await widget.history.exportJson();
    } on Object catch (error) {
      if (!context.mounted) return;
      _showMessage(context, 'Could not build the history file: $error');
      return;
    }
    if (!context.mounted) return;

    if (action == _ExportAction.share) {
      try {
        final shared = await HistoryExport.shareJson(data);
        if (!context.mounted || !shared) return;
        _showMessage(context, 'History shared.');
      } on Object catch (error) {
        if (!context.mounted) return;
        _showMessage(context, 'Could not share history: $error');
      }
      return;
    }

    try {
      final location = await HistoryExport.saveJson(data);
      if (location == null || !context.mounted) return;
      _showMessage(
        context,
        'History exported to ${HistoryExport.describeLocation(location)}',
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      _showMessage(context, 'Could not export history: $error');
    }
  }

  Future<void> _import(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import history'),
        content: const Text(
            'Select a history JSON file to merge with the current history.'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Select file'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    const typeGroup = XTypeGroup(
      label: 'History JSON',
      extensions: <String>['json'],
      mimeTypes: <String>[
        'application/json',
        'text/json',
        'text/plain',
        'application/octet-stream',
      ],
      uniformTypeIdentifiers: <String>['public.json'],
    );

    XFile? file;
    try {
      file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      );
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(context, 'Could not open the file picker: $error');
      return;
    }
    if (file == null || !context.mounted) return;

    String data;
    try {
      data = await file.readAsString();
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(context, 'Could not read the selected file: $error');
      return;
    }
    if (!context.mounted) return;

    ({int imported, int total}) result;
    try {
      result = await widget.history.importHistoryContent(data);
    } on Object catch (error) {
      if (!context.mounted) return;
      _showMessage(context, 'Import failed: $error');
      return;
    }
    if (!context.mounted) return;
    if (result.imported == 0) {
      _showMessage(
        context,
        'No valid history entries found in the selected file.',
      );
      return;
    }
    _showMessage(
      context,
      'Imported ${result.imported} entries '
      '(${result.total} total after merge).',
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
    ));
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.entry,
    required this.busy,
    required this.onOpen,
    required this.onToggleCompleted,
  });

  final HistoryEntry entry;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onToggleCompleted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              PosterThumb(url: entry.poster, width: 42, height: 58),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (entry.latestEpisode.isNotEmpty) ...[
                          Icon(Icons.playlist_play,
                              size: 13, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              entry.latestEpisode,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (MediaQuery.sizeOf(context).width >= 600)
                          StatusPill(
                            label:
                                entry.completed ? 'Completed' : 'In progress',
                            color: entry.completed
                                ? scheme.primary
                                : scheme.tertiary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                IconButton(
                  tooltip: entry.completed
                      ? 'Mark as in progress'
                      : 'Mark as completed',
                  onPressed: onToggleCompleted,
                  icon: Icon(
                    entry.completed ? Icons.undo : Icons.check_circle_outline,
                    size: 20,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(entry.completed ? 'Open' : 'Resume'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
