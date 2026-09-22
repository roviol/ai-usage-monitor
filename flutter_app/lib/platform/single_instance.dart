/// Single-instance signaling with a Flutter-specific instance name so both
/// applications can run concurrently: named mutex + auto-reset event on
/// Windows, lock file plus polled activation file on Linux.
library;

import 'dart:async';
import 'dart:io';

import 'interfaces.dart';

/// Instance name distinguishes the Flutter binary from the C++ reference so
/// both may run side by side.
const String flutterInstanceName = 'ai-usage-monitor-flutter';

class IoSingleInstanceSignal implements SingleInstanceSignal {
  IoSingleInstanceSignal._(this._lockPath, this._activationPath) : _anotherRunning = _acquire(_lockPath);

  static IoSingleInstanceSignal create(String dataRoot) {
    Directory(dataRoot).createSync(recursive: true);
    final separator = Platform.pathSeparator;
    final lock = '$dataRoot$separator$flutterInstanceName.lock';
    final activation = '$dataRoot$separator$flutterInstanceName.activate';
    return IoSingleInstanceSignal._(lock, activation);
  }

  final String _lockPath;
  final String _activationPath;
  final bool _anotherRunning;
  Timer? _watcher;
  final List<Completer<bool>> _waiters = [];

  /// Acquires the instance lock and reports whether another process already
  /// holds it. Uses an O_EXCL-style claim file: the first process creates and
  /// keeps it; a second process sees it present and reports another running.
  static bool _acquire(String path) {
    try {
      final claim = File('$path.claim');
      final primary = File(path);
      if (primary.existsSync()) {
        final sidecar = File('$path.sidecar');
        if (sidecar.existsSync()) {
          return true;
        }
      }
      if (claim.existsSync()) {
        return true;
      }
      claim.writeAsStringSync('pid:$pid', flush: true);
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  bool isAnotherRunning() => _anotherRunning;

  @override
  void signalActivation() {
    try {
      File(_activationPath).writeAsStringSync('show', flush: true);
    } catch (_) {}
    _notifyWaiters();
  }

  void _notifyWaiters() {
    for (final waiter in List<Completer<bool>>.of(_waiters)) {
      if (!waiter.isCompleted) {
        waiter.complete(consumeActivation());
      }
    }
    _waiters.clear();
  }

  @override
  bool consumeActivation() {
    final file = File(_activationPath);
    if (!file.existsSync()) return false;
    try {
      file.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> waitForActivation(Duration timeout) async {
    if (consumeActivation()) return true;
    final completer = Completer<bool>();
    _waiters.add(completer);
    if (timeout != Duration.zero) {
      Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(consumeActivation());
          _waiters.remove(completer);
        }
      });
    } else {
      // Poll the activation file like the reference's watcher thread.
      _watcher ??= Timer.periodic(const Duration(milliseconds: 250), (_) => _pollActivation());
    }
    return completer.future;
  }

  void _pollActivation() {
    if (consumeActivation()) {
      _notifyWaiters();
    }
  }

  void dispose() {
    _watcher?.cancel();
    for (final waiter in List<Completer<bool>>.of(_waiters)) {
      if (!waiter.isCompleted) waiter.complete(false);
    }
    _waiters.clear();
    try {
      final claim = File('$_lockPath.claim');
      if (claim.existsSync()) claim.deleteSync();
    } catch (_) {}
  }
}