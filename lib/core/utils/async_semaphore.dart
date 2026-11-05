import 'dart:async';
import 'dart:collection';

/// A small FIFO concurrency limiter.
///
/// Engine commands can spawn Playwright/Chromium, so letting an enthusiastic
/// user fire ten searches at once is a good way to exhaust memory. The client
/// caps short-lived commands at two concurrent processes.
class AsyncSemaphore {
  AsyncSemaphore(this.maxConcurrent) : assert(maxConcurrent > 0);

  final int maxConcurrent;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();
  int _active = 0;

  int get active => _active;
  int get pending => _waiters.length;

  Future<T> run<T>(Future<T> Function() action) async {
    await _acquire();
    try {
      return await action();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < maxConcurrent) {
      _active++;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      // Transfer the slot directly to the next waiter.
      _waiters.removeFirst().complete();
    } else {
      _active--;
    }
  }
}
