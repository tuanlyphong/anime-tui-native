import 'dart:convert';

import '../core/errors/engine_exception.dart';
import 'models.dart';

final RegExp _ansi = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');
final RegExp _control = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');
final RegExp _episodeSuffix = RegExp(r'\s*\[([^\]]+)\]\s*$');

/// Removes terminal control sequences emitted by the engine's status writer.
String sanitizeLine(String line) => _stripTerminal(line).trim();

String _stripTerminal(String line) {
  var value = line.replaceAll(_ansi, '');
  value = value.replaceAll('\r', '');
  value = value.replaceAll(_control, ' ');
  return value;
}

List<String> cleanLines(Iterable<String> lines) => lines
    .map(sanitizeLine)
    .where((line) => line.isNotEmpty)
    .toList(growable: false);

List<List<String>> parseTsv(Iterable<String> lines) {
  final rows = <List<String>>[];
  for (final raw in lines) {
    final line = _stripTerminal(raw);
    if (line.trim().isEmpty) continue;
    // Do not trim the whole line: a leading tab encodes an empty first field.
    final fields =
        line.split('\t').map((field) => field.trim()).toList(growable: false);
    if (fields.isNotEmpty) rows.add(fields);
  }
  return rows;
}

List<AnimeSummary> parseSearchResults(Iterable<String> lines) {
  final results = <AnimeSummary>[];
  for (final fields in parseTsv(lines)) {
    if (fields.isEmpty) continue;
    final title = fields[0];
    final url = fields.length > 1 ? fields[1] : '';
    if (title.isEmpty && url.isEmpty) continue;
    if (url.isEmpty) {
      // A malformed row is not worth failing the whole search for; the log
      // keeps the raw line available for diagnostics.
      continue;
    }
    results.add(AnimeSummary(
      title: title.isEmpty ? url : title,
      url: url,
      poster: fields.length > 2 ? fields[2] : '',
    ));
  }
  return results;
}

List<Episode> parseEpisodes(Iterable<String> lines) {
  final episodes = <Episode>[];
  for (final fields in parseTsv(lines)) {
    if (fields.length < 2 || fields[1].isEmpty) continue;
    final display = fields[0].isEmpty ? fields[1] : fields[0];
    episodes.add(Episode(
      title: display,
      url: fields[1],
      originalTitle:
          fields.length > 2 && fields[2].isNotEmpty ? fields[2] : display,
      preferred: fields.length > 3 && fields[3] == '1',
      poster: '',
    ));
  }
  return episodes;
}

List<HistoryEntry> parseHistory(Iterable<String> lines,
    {required bool completed}) {
  final entries = <HistoryEntry>[];
  for (final fields in parseTsv(lines)) {
    if (fields.length < 2 || fields[1].isEmpty) continue;
    final rawTitle = fields[0];
    final match = _episodeSuffix.firstMatch(rawTitle);
    entries.add(HistoryEntry(
      title:
          match == null ? rawTitle : rawTitle.substring(0, match.start).trim(),
      url: fields[1],
      poster: fields.length > 2 ? fields[2] : '',
      latestEpisode: match?.group(1)?.trim() ?? '',
      completed: completed,
    ));
  }
  return entries;
}

String parseStreamUrl(Iterable<String> lines) {
  final cleaned = cleanLines(lines);
  if (cleaned.isEmpty) {
    throw EngineException(
      EngineErrorKind.protocol,
      'The engine did not return a stream URL.',
      details: 'stdout was empty',
    );
  }

  // The engine may return either a raw URL or a JSON envelope:
  // {"output": "https://...", "exit_code": 0, "error": null}
  final candidate = _extractJsonOutput(cleaned.last.trim());

  final uri = Uri.tryParse(candidate);
  if (uri == null || !uri.hasScheme || candidate.contains(' ')) {
    throw EngineException(
      EngineErrorKind.protocol,
      'The engine returned an invalid stream URL.',
      details: candidate,
    );
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw EngineException(
      EngineErrorKind.protocol,
      'The engine returned an unsupported stream URL scheme.',
      details: candidate,
    );
  }
  return candidate;
}

/// If the line is a JSON envelope emitted by the engine, extract the URL
/// from the "output" field; otherwise treat the line as a raw URL.
String _extractJsonOutput(String line) {
  try {
    final json = jsonDecode(line);
    if (json is Map<String, dynamic> && json.containsKey('output')) {
      final output = json['output'];
      if (output is String && output.isNotEmpty) {
        return output;
      }
    }
  } catch (_) {
    // Not valid JSON — treat as a raw URL.
  }
  return line;
}

PlaybackOutcome parsePlaybackOutcome(Iterable<String> lines) {
  final cleaned = cleanLines(lines);
  if (cleaned.isEmpty) {
    throw EngineException(
      EngineErrorKind.protocol,
      'The playback command ended without an outcome.',
    );
  }
  return switch (cleaned.last.toLowerCase()) {
    'finished' => PlaybackOutcome.finished,
    'stopped' => PlaybackOutcome.stopped,
    'failed' => PlaybackOutcome.failed,
    final other => throw EngineException(
        EngineErrorKind.protocol,
        'Unknown playback outcome from engine.',
        details: other,
      ),
  };
}

PlaybackStatus? parsePlaybackStatus(String raw) {
  final line = sanitizeLine(raw);
  if (line.isEmpty) return null;

  final percent = RegExp(r'(\d{1,3})%').firstMatch(line);
  final value = percent == null
      ? null
      : (int.tryParse(percent.group(1)!) ?? 0).clamp(0, 100) / 100.0;

  final lower = line.toLowerCase();
  if (lower.startsWith('preparing ') ||
      lower.startsWith('downloading ') ||
      lower.contains('buffered')) {
    return PlaybackStatus(
      stage: PlaybackStage.preparing,
      text: line,
      percent: value,
    );
  }
  // The engine emits "<label> playing 50% · …" (see formatStatus in
  // lib/playback-status.js), not "Playing <label> …". Accept both.
  if (lower.startsWith('playing ') || lower.contains(' playing ')) {
    return PlaybackStatus(
      stage: PlaybackStage.playing,
      text: line,
      percent: value,
    );
  }
  return null;
}
