import 'dart:async';

import 'package:anime_tui_native/engine/engine_command.dart';
import 'package:anime_tui_native/engine/engine_transport.dart';
import 'package:anime_tui_native/engine/models.dart';

class FakeReply {
  const FakeReply({
    this.stdout = const <String>[],
    this.stderr = const <String>[],
    this.exitCode = 0,
    this.hang = false,
    this.spawnError,
  });

  final List<String> stdout;
  final List<String> stderr;
  final int exitCode;
  final bool hang;
  final Object? spawnError;
}

class FakeTransport implements EngineTransport {
  FakeTransport({Map<EngineCommandKind, FakeReply>? replies})
      : replies = replies ?? <EngineCommandKind, FakeReply>{};

  final Map<EngineCommandKind, FakeReply> replies;
  final List<EngineCommand> commands = <EngineCommand>[];
  final List<EngineRun> runs = <EngineRun>[];
  bool disposed = false;

  @override
  Future<EngineRun> start(EngineCommand command) async {
    commands.add(command);
    final reply = replies[command.kind] ?? const FakeReply();
    if (reply.spawnError != null) throw reply.spawnError!;

    final stdout = StreamController<String>();
    final stderr = StreamController<String>();
    final exit = Completer<int>();

    scheduleMicrotask(() async {
      if (!reply.hang) {
        for (final line in reply.stdout) {
          stdout.add(line);
        }
        for (final line in reply.stderr) {
          stderr.add(line);
        }
        await stdout.close();
        await stderr.close();
        if (!exit.isCompleted) exit.complete(reply.exitCode);
      }
    });

    final run = EngineRun(
      id: 'fake-${commands.length}',
      command: command,
      stdout: stdout.stream,
      stderr: stderr.stream,
      exitCode: exit.future,
      startedAt: DateTime.now(),
      stop: () async {
        if (!exit.isCompleted) exit.complete(143);
        if (!stdout.isClosed) await stdout.close();
        if (!stderr.isClosed) await stderr.close();
      },
    );
    runs.add(run);
    return run;
  }

  @override
  Future<EngineHealth> healthCheck() async => EngineHealth.ready(
        nodeVersion: 'v20.11.0',
        enginePath: '/tmp/anime.js',
      );

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
