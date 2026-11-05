import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum LogLevel {
  debug(0, 'DEBUG'),
  info(1, 'INFO'),
  warning(2, 'WARN'),
  error(3, 'ERROR');

  const LogLevel(this.severity, this.label);

  final int severity;
  final String label;

  bool includes(LogLevel other) => other.severity >= severity;
}

@immutable
class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
    this.context = const <String, Object?>{},
  });

  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, Object?> context;

  String toLine() {
    final buffer = StringBuffer()
      ..write(timestamp.toIso8601String())
      ..write(' [')
      ..write(level.label.padRight(5))
      ..write('] ')
      ..write(message);

    if (context.isNotEmpty) {
      buffer.write(' ');
      buffer.write(context.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join(' '));
    }
    if (error != null) {
      buffer.write(' error="');
      buffer.write(error.toString().replaceAll('\n', ' '));
      buffer.write('"');
    }
    if (stackTrace != null) {
      buffer.write('\n');
      buffer.write(stackTrace.toString());
    }
    return buffer.toString();
  }

  String get displayTime {
    final local = timestamp.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

/// Process-wide structured logger with an in-memory ring buffer and a rolling
/// file sink.
///
/// The UI observes the same object, so the "Logs" screen always shows exactly
/// what was written to disk. Logging must never throw — every sink operation is
/// wrapped, because a logger that crashes the app is worse than no logger.
class AppLogger extends ChangeNotifier {
  AppLogger({this.maxEntries = 1000, this.maxFileBytes = 5 * 1024 * 1024});

  static final AppLogger instance = AppLogger();

  final int maxEntries;
  final int maxFileBytes;

  final List<LogEntry> _entries = <LogEntry>[];
  final StreamController<LogEntry> _stream =
      StreamController<LogEntry>.broadcast(sync: true);
  IOSink? _sink;
  File? _file;
  bool _disposed = false;
  bool _notifyScheduled = false;

  List<LogEntry> get entries => List<LogEntry>.unmodifiable(_entries);
  Stream<LogEntry> get stream => _stream.stream;
  File? get file => _file;
  String? get filePath => _file?.path;

  Future<void> init({String? filePath}) async {
    if (filePath == null || filePath.isEmpty) return;
    try {
      final file = File(filePath);
      await file.parent.create(recursive: true);

      if (await file.exists() && await file.length() > maxFileBytes) {
        final rotated = File('$filePath.1');
        if (await rotated.exists()) {
          await rotated.delete();
        }
        await file.rename(rotated.path);
      }

      _file = File(filePath);
      _sink = _file!.openWrite(mode: FileMode.append);
      info('Logger initialised', context: {'file': filePath});
    } on Object catch (error) {
      // Logging is best-effort; keep the in-memory buffer working.
      _entries.add(LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.warning,
        message: 'Could not open log file: $error',
      ));
    }
  }

  void debug(String message, {Map<String, Object?> context = const {}}) =>
      log(LogLevel.debug, message, context: context);

  void info(String message, {Map<String, Object?> context = const {}}) =>
      log(LogLevel.info, message, context: context);

  void warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  }) =>
      log(LogLevel.warning, message,
          error: error, stackTrace: stackTrace, context: context);

  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  }) =>
      log(LogLevel.error, message,
          error: error, stackTrace: stackTrace, context: context);

  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  }) {
    if (_disposed) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );

    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }

    _safeFileWrite(entry);

    if (!_stream.isClosed) {
      _stream.add(entry);
    }

    if (kDebugMode) {
      debugPrint(entry.toLine());
    }

    // Coalesce UI notifications: a burst of logs should not cause a burst of
    // rebuilds inside a single frame.
    if (!_notifyScheduled && !_disposed) {
      _notifyScheduled = true;
      scheduleMicrotask(() {
        _notifyScheduled = false;
        if (!_disposed) notifyListeners();
      });
    }
  }

  void _safeFileWrite(LogEntry entry) {
    final sink = _sink;
    if (sink == null) return;
    try {
      sink.writeln(entry.toLine());
    } on Object {
      // Never let a broken pipe take down the app.
    }
  }

  Future<void> flush() async {
    try {
      await _sink?.flush();
    } on Object {
      // ignore
    }
  }

  void clear() {
    _entries.clear();
    if (!_disposed) notifyListeners();
  }

  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _sink?.flush();
      await _sink?.close();
    } on Object {
      // ignore
    }
    _sink = null;
    await _stream.close();
    super.dispose();
  }

  @override
  void dispose() {
    // The singleton outlives widgets; closing is explicit via [close].
    if (!_disposed) {
      _disposed = true;
      _stream.close();
      _sink?.close();
    }
    super.dispose();
  }
}
