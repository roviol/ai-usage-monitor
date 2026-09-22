import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_usage_monitor/app_controller.dart';
import 'package:ai_usage_monitor/config/config.dart';
import 'package:ai_usage_monitor/domain/domain.dart';
import 'package:ai_usage_monitor/platform/platform.dart';
import 'package:ai_usage_monitor/providers/providers.dart';
import 'package:ai_usage_monitor/scheduler/scheduler.dart';

class StubProvider extends UsageProvider {
  StubProvider(this._config, {this.result, this.error, this.delay = Duration.zero});

  final ProviderConfig _config;
  final ProviderSnapshot? result;
  final Object? error;
  final Duration delay;
  int refreshCount = 0;

  @override
  ProviderConfig get config => _config;

  @override
  void cancel() {}

  @override
  ProviderCapabilities capabilities() => const ProviderCapabilities();

  @override
  Future<ConnectionTestResult> testConnection() async =>
      const ConnectionTestResult(success: true, capabilities: ProviderCapabilities(), message: 'ok');

  @override
  Future<ProviderSnapshot> refresh() async {
    refreshCount++;
    await Future<void>.delayed(delay);
    final error = this.error;
    if (error != null) throw error;
    return result!;
  }
}

ProviderConfig enabledConfig(String id, {ProviderKind kind = ProviderKind.openAiCompatible}) => ProviderConfig(
      id: id,
      name: id,
      kind: kind,
      enabled: true,
      executable: 'exe',
      baseUrl: 'https://example.com',
      usagePath: '/usage',
      jsonPointers: {'used_percent': '/percent'},
    );

ProviderSnapshot freshSnapshot(String id) {
  final snapshot = ProviderSnapshot(
    providerId: id,
    displayName: id,
    kind: ProviderKind.openAiCompatible,
    observedAt: DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true),
    freshness: Freshness.fresh,
    health: Health.healthy,
  );
  snapshot.metrics.add(Metric(
    kind: MetricKind.usedPercent,
    value: '10',
    unit: MetricUnit.percent,
    scope: MetricScope.billingPeriod,
    availability: Availability.available,
    label: 'Uso',
  ));
  return snapshot;
}

ProviderSnapshot errorSnapshot(String id, String code) {
  final snapshot = ProviderSnapshot(
    providerId: id,
    displayName: id,
    kind: ProviderKind.openAiCompatible,
    observedAt: DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true),
    freshness: Freshness.noData,
    health: Health.error,
  );
  snapshot.error = ProviderError(code, 'boom', transient: true);
  return snapshot;
}

class FakeUsageProvider extends UsageProvider {
  FakeUsageProvider(this._config, {this.snapshot, this.throwable});

  final ProviderConfig _config;
  final ProviderSnapshot? snapshot;
  final Object? throwable;
  int refreshes = 0;
  bool cancelled = false;

  @override
  ProviderConfig get config => _config;

  @override
  ProviderCapabilities capabilities() => const ProviderCapabilities();

  @override
  Future<ConnectionTestResult> testConnection() async =>
      const ConnectionTestResult(success: true, capabilities: ProviderCapabilities(), message: 'ok');

  @override
  Future<ProviderSnapshot> refresh() async {
    refreshes++;
    final throwable = this.throwable;
    if (throwable != null) throw throwable;
    return snapshot!;
  }

  @override
  void cancel() => cancelled = true;
}

void main() {
  group('RefreshScheduler interval', () {
    test('validates 1..60 minutes', () {
      final scheduler = RefreshScheduler(clock: FakeClock(), onSnapshot: (_) {});
      expect(() => scheduler.setInterval(Duration.zero), throwsArgumentError);
      expect(() => scheduler.setInterval(const Duration(minutes: 61)), throwsArgumentError);
      expect(() => scheduler.setInterval(const Duration(minutes: 5)), returnsNormally);
      expect(() => scheduler.setInterval(const Duration(minutes: 1)), returnsNormally);
      expect(() => scheduler.setInterval(const Duration(minutes: 60)), returnsNormally);
    });

    test('interval is applied to next due time after success', () async {
      final clock = FakeClock();
      final provider = FakeUsageProvider(enabledConfig('a'), snapshot: freshSnapshot('a'));
      final scheduler = RefreshScheduler(clock: clock, onSnapshot: (_) {});
      scheduler.setProviders([provider]);
      scheduler.setInterval(const Duration(minutes: 7));
      // Providers are due immediately at startup, like the reference.
      scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(provider.refreshes, 1);
      final due = scheduler.nextDueFor('a')!;
      expect(due.difference(clock.now()).inMinutes, 7);
      scheduler.stop();
    });

    test('cannot replace providers while running', () {
      final scheduler = RefreshScheduler(clock: FakeClock(), onSnapshot: (_) {});
      scheduler.setProviders([]);
      scheduler.start();
      expect(
        () => scheduler.setProviders([]),
        throwsStateError,
      );
      scheduler.stop();
    });
  });

  group('RefreshScheduler backoff', () {
    test('doubles up to the 60-minute cap', () {
      final scheduler = RefreshScheduler(clock: FakeClock(), onSnapshot: (_) {});
      // Base 30s with jitter in 0..5 for a short id; bounds mirror the
      // reference (cap 30s+jitter for failures=1, jitter < capped/5).
      final first = scheduler.backoff(0, 'p');
      expect(first.inSeconds, inInclusiveRange(30, 35));
      expect(scheduler.backoff(1, 'p'), first);
      final third = scheduler.backoff(3, 'p');
      expect(third.inSeconds, inInclusiveRange(120, 120 + 24));
      final huge = scheduler.backoff(20, 'p');
      expect(huge, lessThanOrEqualTo(const Duration(minutes: 60)));
    });

    test('jitter is deterministic per provider', () {
      final scheduler = RefreshScheduler(clock: FakeClock(), onSnapshot: (_) {});
      expect(scheduler.backoff(5, 'alpha'), scheduler.backoff(5, 'alpha'));
      expect(scheduler.backoff(5, 'alpha'), isNot(scheduler.backoff(5, 'beta')));
    });

    test('Retry-After overrides upward', () async {
      final clock = FakeClock();
      final provider = FakeUsageProvider(
        enabledConfig('a'),
        throwable: ProviderException(
          ProviderError('rate-limited', 'rate limited', transient: true, retryAfter: const Duration(minutes: 20)),
        ),
      );
      final scheduler = RefreshScheduler(clock: clock, onSnapshot: (_) {});
      scheduler.setProviders([provider]);
      scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final due = scheduler.nextDueFor('a')!;
      expect(due.difference(clock.now()).inMinutes, greaterThanOrEqualTo(20));
      scheduler.stop();
    });

    test('recovery resets failure count', () async {
      final clock = FakeClock();
      var fail = true;
      ProviderSnapshot snapshot() => fail ? errorSnapshot('a', 'http-500') : freshSnapshot('a');
      final provider = _DynamicProvider(enabledConfig('a'), () => snapshot());
      final snapshots = <ProviderSnapshot>[];
      final scheduler = RefreshScheduler(clock: clock, onSnapshot: snapshots.add);
      scheduler.setProviders([provider]);
      scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(provider.refreshes, 1);
      expect(scheduler.nextDueFor('a')!.difference(clock.now()).inSeconds, greaterThanOrEqualTo(30));
      fail = false;
      scheduler.refreshAll();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(snapshots.last.health, Health.healthy);
      // After recovery the provider is due at interval, not backoff.
      expect(scheduler.nextDueFor('a')!.difference(clock.now()).inMinutes, 5);
      scheduler.stop();
    });
  });

  group('RefreshScheduler coalescing and concurrency', () {
    test('queued refreshes coalesce', () async {
      final provider = _DelayedProvider(enabledConfig('a'), freshSnapshot('a'), const Duration(milliseconds: 120));
      final snapshots = <ProviderSnapshot>[];
      final scheduler = RefreshScheduler(clock: FakeClock(), onSnapshot: snapshots.add);
      scheduler.setProviders([provider]);
      scheduler.start();
      // Wait until the first refresh is in flight.
      var guard = 0;
      while (!provider.refreshing && guard++ < 200) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(provider.refreshes, 1);
      // Repeated manual refreshes while in flight coalesce into one queued
      // run, like the reference's queued flag.
      for (var i = 0; i < 10; i++) {
        scheduler.refreshOne('a');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(provider.refreshes, 2);
      scheduler.stop();
    });

    test('at most two refreshes run concurrently', () async {
      final providers = <_DelayedProvider>[
        for (final id in ['a', 'b', 'c', 'd'])
          _DelayedProvider(enabledConfig(id), freshSnapshot(id), const Duration(milliseconds: 100)),
      ];
      final scheduler = RefreshScheduler(clock: FakeClock(), onSnapshot: (_) {});
      scheduler.setProviders(providers);
      scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final inFlight = providers.where((p) => p.refreshing).length;
      expect(inFlight, lessThanOrEqualTo(2));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(providers.every((p) => p.refreshes >= 1), isTrue);
      scheduler.stop();
    });
  });

  group('AppController stale preservation', () {
    test('error after valid snapshot keeps metrics marked stale', () {
      final controller = _TestControllerBuilder.empty();
      controller.applySettings(Settings(providers: [enabledConfig('a')]));
      controller.receiveSnapshot(freshSnapshot('a'));
      controller.receiveSnapshot(errorSnapshot('a', 'http-500'));
      final published = controller.orderedSnapshots().single;
      expect(published.freshness, Freshness.stale);
      expect(published.health, Health.error);
      expect(published.metrics.single.value, '10');
      expect(published.error!.code, 'http-500');
    });

    test('refreshing marks in-flight providers', () {
      final controller = _TestControllerBuilder.empty();
      controller.applySettings(Settings(providers: [enabledConfig('a')]));
      controller.markRefreshing('a');
      final snapshot = controller.orderedSnapshots().single;
      expect(snapshot.error!.code, 'refreshing');
      expect(snapshot.health, Health.partial);
    });

    test('cache keeps only snapshots with metrics', () {
      final controller = _TestControllerBuilder.empty();
      controller.applySettings(Settings(providers: [enabledConfig('a'), enabledConfig('b')]));
      controller.receiveSnapshot(freshSnapshot('a'));
      controller.receiveSnapshot(errorSnapshot('b', 'x'));
      final cache = controller.orderedSnapshots();
      expect(cache, hasLength(2));
      expect(cache.where((s) => s.metrics.isNotEmpty).length, 1);
    });
  });
}

class _DynamicProvider extends UsageProvider {
  _DynamicProvider(this._config, this.snapshotFactory);

  final ProviderConfig _config;
  final ProviderSnapshot Function() snapshotFactory;
  int refreshes = 0;

  @override
  ProviderConfig get config => _config;

  @override
  ProviderCapabilities capabilities() => const ProviderCapabilities();

  @override
  Future<ConnectionTestResult> testConnection() async =>
      const ConnectionTestResult(success: true, capabilities: ProviderCapabilities(), message: 'ok');

  @override
  Future<ProviderSnapshot> refresh() async {
    refreshes++;
    return snapshotFactory();
  }

  @override
  void cancel() {}
}

class _DelayedProvider extends UsageProvider {
  _DelayedProvider(this._config, ProviderSnapshot snapshot, this.delay)
      : _snapshot = snapshot;

  final ProviderConfig _config;
  final ProviderSnapshot _snapshot;
  final Duration delay;
  int refreshes = 0;
  bool refreshing = false;

  @override
  ProviderConfig get config => _config;

  @override
  ProviderCapabilities capabilities() => const ProviderCapabilities();

  @override
  Future<ConnectionTestResult> testConnection() async =>
      const ConnectionTestResult(success: true, capabilities: ProviderCapabilities(), message: 'ok');

  @override
  Future<ProviderSnapshot> refresh() async {
    refreshes++;
    refreshing = true;
    await Future<void>.delayed(delay);
    refreshing = false;
    return _snapshot;
  }

  @override
  void cancel() {}
}

class _TestControllerBuilder {
  static AppController empty() {
    final temp = Directory.systemTemp.createTempSync('controller_empty');
    addTearDown(() => temp.deleteSync(recursive: true));
    final controller = AppController(
      clock: FakeClock(),
      http: FakeHttpTransport(),
      process: FakeProcessRunner(),
      secrets: FakeSecretStore(),
      instanceSignal: FakeSingleInstanceSignal(),
      executablePath: temp.path,
    );
    return controller;
  }
}