/// Refresh scheduler ported from the C++ reference: interval validation, at
/// most two concurrent refreshes, queued coalescing, the reference exponential
/// backoff with deterministic per-provider jitter, `Retry-After` override,
/// failure counting and error mapping to snapshots.
library;

import 'dart:async';

import '../domain/model.dart';
import '../domain/validate.dart';
import '../platform/interfaces.dart';
import '../providers/providers.dart';

/// Per-provider runtime state.
class ProviderState {
  ProviderState({required this.provider});

  final UsageProvider provider;
  DateTime nextDue = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  int failures = 0;
  bool queued = false;
  bool running = false;
}

/// Schedules provider refreshes on the shared interval with the reference's
/// backoff, honoring manual refreshes and a two-slot concurrency cap.
class RefreshScheduler {
  RefreshScheduler({
    required Clock clock,
    required this.onSnapshot,
    int maxConcurrent = 2,
  })  : _clock = clock,
        _maxConcurrent = maxConcurrent;

  final Clock _clock;
  final void Function(ProviderSnapshot snapshot) onSnapshot;
  final int _maxConcurrent;

  final Map<String, ProviderState> _providers = {};
  Duration _interval = const Duration(minutes: 5);
  Timer? _timer;
  int _active = 0;
  bool _started = false;
  final List<String> _jobs = [];

  /// Replaces the provider set; requires the scheduler to be stopped.
  void setProviders(List<UsageProvider> providers) {
    if (_started) {
      throw StateError('cannot replace providers while scheduler is running');
    }
    _providers.clear();
    for (final provider in providers) {
      _providers[provider.config.id] = ProviderState(provider: provider);
    }
  }

  /// Validates and applies the refresh interval (1..60 minutes).
  void setInterval(Duration interval) {
    if (interval < const Duration(minutes: 1) || interval > const Duration(minutes: 60)) {
      throw ArgumentError.value(interval, 'interval', 'refresh interval must be 1..60 minutes');
    }
    _interval = interval;
  }

  Duration get interval => _interval;

  void start() {
    if (_started) return;
    _started = true;
    _tick();
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
    _jobs.clear();
    _active = 0;
    _providers.forEach((_, state) => state.running = false);
  }

  /// Queues every provider for an immediate refresh; repeated calls while a
  /// refresh is pending coalesce into the same queued flag.
  void refreshAll() {
    _providers.forEach((_, state) {
      state.queued = true;
    });
    _wake();
  }

  /// Queues one provider by id.
  void refreshOne(String providerId) {
    final state = _providers[providerId];
    if (state != null) {
      state.queued = true;
    }
    _wake();
  }

  /// Notifies the scheduler that the clock changed (wake early).
  void notifyClockChanged() => _wake();

  void _wake() {
    if (!_started) return;
    _tick();
  }

  void _scheduleNext() {
    if (!_started) return;
    _timer?.cancel();
    _timer = null;
    _tick();
  }

  void _tick() {
    final now = _clock.now();
    // Start jobs while concurrency allows, in configuration order.
    for (final state in _providers.values) {
      if (_active >= _maxConcurrent) break;
      if (state.running) continue;
      if (state.queued || !state.nextDue.isAfter(now)) {
        state.queued = false;
        state.running = true;
        _active++;
        unawaited(_run(state, now));
      }
    }
    _timer ??= Timer(_nextWake(now), _scheduleNext);
  }

  Duration _nextWake(DateTime now) {
    var earliest = const Duration(days: 3650);
    for (final state in _providers.values) {
      if (state.running) continue;
      if (state.queued) return Duration.zero;
      final due = state.nextDue.difference(now);
      if (due < earliest) earliest = due;
    }
    return earliest < Duration.zero ? Duration.zero : earliest;
  }

  Future<void> _run(ProviderState state, DateTime now) async {
    final snapshot = await _refresh(state, now);
    // Update scheduling state under the same rules as the reference.
    final updatedNow = _clock.now();
    if (snapshot.health == Health.error) {
      state.failures++;
      var delay = backoff(state.failures, state.provider.config.id);
      final retryAfter = snapshot.error?.retryAfter;
      if (retryAfter != null && retryAfter > delay) {
        delay = retryAfter;
      }
      state.nextDue = updatedNow.add(delay);
    } else {
      state.failures = 0;
      state.nextDue = updatedNow.add(_interval);
    }
    state.running = false;
    _active = _active > 0 ? _active - 1 : 0;
    onSnapshot(snapshot);
    _scheduleNext();
  }

  /// Runs one refresh and maps failures onto error snapshots, mirroring the
  /// reference's `RefreshScheduler::Refresh`.
  Future<ProviderSnapshot> _refresh(ProviderState state, DateTime now) async {
    ProviderSnapshot snapshot;
    try {
      final result = await state.provider.refresh().timeout(
            _interval + const Duration(minutes: 1),
          );
      final validation = validateSnapshot(result);
      if (!validation.valid) {
        throw Exception(validation.errors.first);
      }
      snapshot = result;
    } catch (error) {
      snapshot = ProviderSnapshot(
        providerId: state.provider.config.id,
        displayName: state.provider.config.name,
        kind: state.provider.config.kind,
        observedAt: now,
        freshness: Freshness.noData,
        health: Health.error,
      );
      if (error is ProviderException) {
        snapshot.error = error.error;
      } else {
        snapshot.error = ProviderError('refresh-failed', error.toString(), transient: true);
      }
    }
    return snapshot;
  }

  /// The reference backoff: 30s * 2^(failures-1) capped at 60 minutes plus a
  /// deterministic per-provider jitter of up to one fifth of the capped base,
  /// with the sum capped at 60 minutes.
  Duration backoff(int failures, String providerId) {
    final exponent = failures == 0 ? 0 : (failures - 1).clamp(0, 7);
    final baseSeconds = 30 * (1 << exponent);
    final capped = baseSeconds > 3600 ? 3600 : baseSeconds;
    final jitterRange = capped ~/ 5 < 1 ? 1 : capped ~/ 5;
    final jitter = providerId.hashCode.abs() % jitterRange;
    final total = capped + jitter > 3600 ? 3600 : capped + jitter;
    return Duration(seconds: total);
  }

  /// Test/inspection hooks.
  bool isRunning(String providerId) => _providers[providerId]?.running ?? false;

  bool isQueued(String providerId) => _providers[providerId]?.queued ?? false;

  DateTime? nextDueFor(String providerId) => _providers[providerId]?.nextDue;
}