import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import '../engine/models.dart';
import '../state/app_controller.dart';
import 'widgets/common.dart';

Future<void> showSettingsDialog(
  BuildContext context,
  AppController controller,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => SettingsDialog(controller: controller),
  );
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _enginePath;
  late final TextEditingController _nodeExecutable;
  late final TextEditingController _workingDirectory;
  late final TextEditingController _timeoutSeconds;
  late final TextEditingController _abyssJar;
  late final TextEditingController _proxy;
  late final TextEditingController _player;

  late String _quality;
  late bool _progressive;
  bool _testing = false;
  bool _saving = false;
  EngineHealth? _testResult;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    _enginePath = TextEditingController(text: settings.enginePath);
    _nodeExecutable = TextEditingController(text: settings.nodeExecutable);
    _workingDirectory = TextEditingController(text: settings.workingDirectory);
    _timeoutSeconds =
        TextEditingController(text: settings.networkTimeoutSeconds.toString());
    _abyssJar = TextEditingController(text: settings.abyssJar);
    _proxy = TextEditingController(text: settings.proxy);
    _player = TextEditingController(text: settings.player);
    _quality = settings.quality;
    _progressive = settings.progressivePlayback;
  }

  @override
  void dispose() {
    _enginePath.dispose();
    _nodeExecutable.dispose();
    _workingDirectory.dispose();
    _timeoutSeconds.dispose();
    _abyssJar.dispose();
    _proxy.dispose();
    _player.dispose();
    super.dispose();
  }

  AppSettings _candidate() {
    final timeout = int.tryParse(_timeoutSeconds.text.trim()) ?? 120;
    return AppSettings(
      enginePath: _enginePath.text.trim(),
      nodeExecutable: _nodeExecutable.text.trim().isEmpty
          ? 'node'
          : _nodeExecutable.text.trim(),
      workingDirectory: _workingDirectory.text.trim(),
      networkTimeoutSeconds: timeout.clamp(15, 900),
      quality: _quality,
      progressivePlayback: _progressive,
      abyssJar: _abyssJar.text.trim(),
      proxy: _proxy.text.trim(),
      player: _player.text.trim().isEmpty ? 'mpv' : _player.text.trim(),
    );
  }

  Future<void> _detectEngine() async {
    final discovered = AppSettings.discoverEnginePath();
    if (discovered.isEmpty) {
      setState(() => _error =
          'Could not find anime.js. Set ANIME_TUI_ENGINE_PATH or enter the path manually.');
      return;
    }
    setState(() {
      _enginePath.text = discovered;
      _error = null;
      _testResult = null;
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
      _error = null;
    });
    try {
      final result = await widget.controller.testSettings(_candidate());
      if (!mounted) return;
      setState(() => _testResult = result);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final timeout = int.tryParse(_timeoutSeconds.text.trim());
    if (timeout == null || timeout < 15 || timeout > 900) {
      setState(() =>
          _error = 'Timeout must be a number between 15 and 900 seconds.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.applySettings(_candidate());
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not save settings: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = math.min(640.0, MediaQuery.sizeOf(context).width - 80);
    final engineExists = _enginePath.text.trim().isNotEmpty &&
        File(_enginePath.text.trim()).existsSync();

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                Icon(Icons.settings_suggest, color: scheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Engine settings')),
        ],
      ),
      content: SizedBox(
        width: width,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The Flutter app spawns the Node.js engine once per command. '
                'Point it at the anime-tui engine script (anime.js).',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 18),
              _field(
                context,
                label: 'Engine script (anime.js)',
                controller: _enginePath,
                hint: '/path/to/anime-tui-cross/anime.js',
                helper: engineExists
                    ? 'File found'
                    : 'File not found — check the path',
                helperColor: engineExists ? scheme.primary : scheme.error,
                suffix: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: _testing || _saving ? null : _detectEngine,
                      child: const Text('Detect'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _field(
                      context,
                      label: 'Node.js executable',
                      controller: _nodeExecutable,
                      hint: 'node',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      context,
                      label: 'Network timeout (seconds)',
                      controller: _timeoutSeconds,
                      hint: '120',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _field(
                context,
                label: 'Working directory (optional)',
                controller: _workingDirectory,
                hint: 'Defaults to the engine script directory',
              ),
              const SizedBox(height: 18),
              Text(
                'Playback',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _field(
                      context,
                      label: 'Player executable',
                      controller: _player,
                      hint: 'mpv',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _quality,
                      decoration: const InputDecoration(labelText: 'Quality'),
                      items: const [
                        DropdownMenuItem(value: 'h', child: Text('High (h)')),
                        DropdownMenuItem(value: 'm', child: Text('Medium (m)')),
                        DropdownMenuItem(value: 'l', child: Text('Low (l)')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _quality = value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Progressive playback'),
                subtitle: const Text(
                  'Start watching while the episode downloads. Disable to download first.',
                ),
                value: _progressive,
                onChanged: (value) => setState(() => _progressive = value),
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 8),
                title: const Text('Advanced'),
                subtitle: const Text('Abyss downloader and proxy'),
                children: [
                  _field(
                    context,
                    label: 'abyss-dl.jar path (optional)',
                    controller: _abyssJar,
                    hint: '/path/to/abyss-dl.jar',
                  ),
                  const SizedBox(height: 12),
                  _field(
                    context,
                    label: 'Proxy (optional)',
                    controller: _proxy,
                    hint: 'http://user:pass@host:port',
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: scheme.error, fontSize: 12),
                  ),
                ),
              ],
              if (_testResult != null) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusPill(
                      label: _testResult!.ready ? 'Ready' : 'Not ready',
                      color: _testResult!.ready ? scheme.primary : scheme.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _testResult!.message,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          onPressed: _testing || _saving ? null : _testConnection,
          icon: _testing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.wifi_tethering, size: 18),
          label: const Text('Test'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: const Text('Save'),
        ),
      ],
    );
  }

  Widget _field(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    String? hint,
    String? helper,
    Color? helperColor,
    TextInputType? keyboardType,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperStyle: helperColor == null ? null : TextStyle(color: helperColor),
        suffixIcon: suffix == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 4),
                child: suffix,
              ),
        suffixIconConstraints: suffix == null
            ? null
            : const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }
}
