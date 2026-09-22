/// Application orchestration ported from the C++ `MonitorApp`:
/// startup ordering, cache preload, `PublishSnapshots` ordering,
/// `MarkRefreshing`, stale preservation and cache writes on successful
/// snapshots.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/settings.dart';
import '../config/store.dart';
import '../config/validation.dart';
import '../domain/model.dart';
import '../platform/interfaces.dart';
import '../platform/io_impl.dart';
import '../providers/providers.dart';
import '../scheduler/scheduler.dart';

/// Holds settings and ordered snapshots, drives the scheduler and notifies
/// widgets on every change.
class AppController extends ChangeNotifier {
  AppController({
    required Clock clock,
    required HttpTransport http,
    required ProcessRunner process,
    required SecretStore secrets,
    required SingleInstanceSignal instanceSignal,
    String? executablePath,
  })  : _clock = clock,
        _http = http,
        _process = process,
        _secrets = secrets,
        _instanceSignal = instanceSignal {
    _paths = resolveDataPaths(executablePath ?? ExecutableLocator.resolve());
  }

  final Clock _clock;
  final HttpTransport _http;
  final ProcessRunner _process;
  final SecretStore _secrets;
  final SingleInstanceSignal _instanceSignal;

  /// The single-instance signal, exposed for the startup activation watcher.
  SingleInstanceSignal get instanceSignal => _instanceSignal;

  /// The platform secret store, exposed for the settings interface.
  SecretStore get secrets => _secrets;

  late final DataPaths _paths;
  Settings _settings = Settings();
  final Map<String, ProviderSnapshot> _snapshots = {};
  RefreshScheduler? _scheduler;

  DataPaths get paths => _paths;

  Settings get settings => _settings;

  bool get recoveredBackup => _recoveredBackup;
  bool _recoveredBackup = false;

  bool get trayNotice => false;

  /// Ordered snapshots in configuration order, with waiting placeholders for
  /// providers without data.
  List<ProviderSnapshot> orderedSnapshots() {
    final ordered = <ProviderSnapshot>[];
    for (final config in _settings.providers) {
      final found = _snapshots[config.id];
      if (found != null) {
        ordered.add(found);
      } else {
        final placeholder = ProviderSnapshot(
          providerId: config.id,
          displayName: config.name,
          kind: config.kind,
        );
        placeholder.health = config.enabled ? Health.partial : Health.disabled;
        placeholder.freshness = Freshness.noData;
        if (config.enabled) {
          placeholder.error = ProviderError('waiting', 'Esperando primera actualización', transient: true);
        }
        ordered.add(placeholder);
      }
    }
    return ordered;
  }

  /// Startup: resolve paths, load settings and cache, apply defaults, rebuild
  /// providers and start refreshing.
  Future<void> startup() async {
    final loaded = loadSettings(_paths);
    _settings = loaded.settings;
    _recoveredBackup = loaded.recoveredBackup;
    await ensureDefaults();
    for (final snapshot in loadCache(_paths)) {
      _snapshots[snapshot.providerId] = snapshot;
    }
    _applyScheduler();
    publishSnapshots();
    notifyListeners();
  }

  /// First-run defaults: discovered Codex and Claude clients plus a disabled
  /// DeepSeek provider, persisted once.
  Future<void> ensureDefaults() async {
    if (_settings.providers.isNotEmpty) return;
    if (discoverExecutable('codex') != null) {
      _settings.providers.add(ProviderConfig(
        id: 'codex',
        name: 'Codex',
        kind: ProviderKind.codex,
        enabled: true,
        executable: 'codex',
      ));
    }
    if (discoverExecutable('claude') != null) {
      _settings.providers.add(ProviderConfig(
        id: 'claude',
        name: 'Claude',
        kind: ProviderKind.claudeSubscription,
        enabled: true,
        executable: 'claude',
      ));
    }
    _settings.providers.add(ProviderConfig(
      id: 'deepseek',
      name: 'DeepSeek',
      kind: ProviderKind.deepSeek,
      baseUrl: 'https://api.deepseek.com',
      balancePath: '/user/balance',
    ));
    saveSettings(_paths, _settings);
  }

  /// Normalizes absolute executable references to portable command names
  /// when they refer to the discovered executable.
  bool makeExecutableReferencesPortable() {
    var changed = false;
    for (final provider in _settings.providers) {
      final command = switch (provider.kind) {
        ProviderKind.codex => 'codex',
        ProviderKind.claudeSubscription => 'claude',
        _ => null,
      };
      if (command == null) continue;
      final portable = makeExecutableReferencePortable(
        command,
        provider.executable,
        discoverExecutable(command),
      );
      if (portable != provider.executable) {
        provider.executable = portable;
        changed = true;
      }
    }
    return changed;
  }

  void _applyScheduler() {
    final scheduler = RefreshScheduler(clock: _clock, onSnapshot: receiveSnapshot);
    final providers = <UsageProvider>[];
    for (final config in _settings.providers) {
      if (!config.enabled) continue;
      final runtimeConfig = config.copy();
      final command = switch (config.kind) {
        ProviderKind.codex => 'codex',
        ProviderKind.claudeSubscription => 'claude',
        _ => null,
      };
      if (command != null) {
        if (runtimeConfig.executable.isEmpty) runtimeConfig.executable = command;
        if (!runtimeConfig.executable.contains('/') && !runtimeConfig.executable.contains('\\')) {
          final found = discoverExecutable(runtimeConfig.executable);
          if (found != null) runtimeConfig.executable = found;
        }
      }
      providers.add(createProvider(runtimeConfig, _http, _process, _secrets, _clock));
    }
    scheduler.setProviders(providers);
    scheduler.setInterval(Duration(minutes: _settings.refreshMinutes));
    scheduler.start();
    scheduler.refreshAll();
    _scheduler = scheduler;
  }

  /// Stops and rebuilds all providers after a settings change.
  void rebuildProviders() {
    _scheduler?.stop();
    _applyScheduler();
  }

  /// Re-publishes ordered snapshots and writes the cache with only snapshots
  /// that carry metrics.
  void publishSnapshots() {
    notifyListeners();
    final cache = [
      for (final snapshot in orderedSnapshots())
        if (snapshot.metrics.isNotEmpty) snapshot,
    ];
    try {
      saveCache(_paths, cache);
    } catch (_) {}
  }

  /// Applies a published snapshot with the reference's stale-preservation
  /// rule: an error over an existing valid snapshot keeps its metrics marked
  /// stale with the new error.
  void receiveSnapshot(ProviderSnapshot snapshot) {
    final existing = _snapshots[snapshot.providerId];
    if (snapshot.health == Health.error && existing != null && existing.metrics.isNotEmpty) {
      final stale = existing.copy();
      stale.freshness = Freshness.stale;
      stale.health = Health.error;
      stale.error = snapshot.error?.copy();
      _snapshots[snapshot.providerId] = stale;
    } else {
      _snapshots[snapshot.providerId] = snapshot;
    }
    publishSnapshots();
  }

  /// Marks an in-flight refresh with the `refreshing` notice.
  void markRefreshing(String providerId) {
    ProviderConfig? config;
    for (final candidate in _settings.providers) {
      if (candidate.id == providerId) {
        config = candidate;
        break;
      }
    }
    if (config == null || !config.enabled) return;
    final snapshot = _snapshots.putIfAbsent(
      providerId,
      () => ProviderSnapshot(
        providerId: config!.id,
        displayName: config.name,
        kind: config.kind,
      ),
    );
    snapshot.providerId = config.id;
    snapshot.displayName = config.name;
    snapshot.kind = config.kind;
    snapshot.health = Health.partial;
    if (snapshot.metrics.isNotEmpty) snapshot.freshness = Freshness.stale;
    snapshot.error = ProviderError('refreshing', 'Actualizando…', transient: true);
  }

  /// Manual refresh of every provider.
  void refreshAll() {
    final scheduler = _scheduler;
    if (scheduler == null) return;
    for (final provider in _settings.providers) {
      markRefreshing(provider.id);
    }
    publishSnapshots();
    scheduler.refreshAll();
  }

  /// Manual refresh of one provider.
  void refreshOne(String providerId) {
    markRefreshing(providerId);
    publishSnapshots();
    _scheduler?.refreshOne(providerId);
  }

  /// Applies new settings, rebuilding providers when the provider set or the
  /// interval changed.
  void applySettings(Settings settings) {
    final previousProviders = _settings.providers;
    final previousRefresh = _settings.refreshMinutes;
    _settings = settings;
    final changed = !_listEquals(previousProviders, settings.providers) ||
        previousRefresh != settings.refreshMinutes;
    if (changed) {
      rebuildProviders();
    }
    publishSnapshots();
  }

  bool _listEquals(List<ProviderConfig> a, List<ProviderConfig> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _scheduler?.stop();
    super.dispose();
  }
}

/// Resolves the running executable path (used to find the portable data
/// directory), overridable for tests.
class ExecutableLocator {
  ExecutableLocator._();

  static String? overridePath;

  static String resolve() {
    if (overridePath != null) return overridePath!;
    try {
      return Platform.resolvedExecutable;
    } catch (_) {
      return Directory.current.path;
    }
  }
}