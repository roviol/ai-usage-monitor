/// Settings and provider configuration models with reference defaults.
library;

import '../domain/overlay_types.dart';
import '../domain/model.dart';

/// Overlay window preferences.
class OverlaySettings {
  OverlaySettings({
    this.enabled = false,
    this.visible = true,
    this.opacity = 78,
    this.locked = true,
    this.corner = OverlayCorner.topRight,
    this.monitor = '',
    this.margin = 12,
    this.suppressFullscreen = false,
  });

  bool enabled;
  bool visible;
  int opacity;
  bool locked;
  OverlayCorner corner;
  String monitor;
  int margin;
  bool suppressFullscreen;

  OverlaySettings copy() => OverlaySettings(
        enabled: enabled,
        visible: visible,
        opacity: opacity,
        locked: locked,
        corner: corner,
        monitor: monitor,
        margin: margin,
        suppressFullscreen: suppressFullscreen,
      );

  @override
  bool operator ==(Object other) =>
      other is OverlaySettings &&
      other.enabled == enabled &&
      other.visible == visible &&
      other.opacity == opacity &&
      other.locked == locked &&
      other.corner == corner &&
      other.monitor == monitor &&
      other.margin == margin &&
      other.suppressFullscreen == suppressFullscreen;

  @override
  int get hashCode => Object.hash(enabled, visible, opacity, locked, corner, monitor, margin, suppressFullscreen);
}

/// Configuration of one monitored provider.
class ProviderConfig {
  ProviderConfig({
    this.id = '',
    this.name = '',
    this.kind = ProviderKind.openAiCompatible,
    this.enabled = false,
    this.executable = '',
    this.baseUrl = '',
    this.encryptedApiKey = '',
    this.encryptedCloudKey = '',
    this.usagePath = '',
    this.balancePath = '',
    Map<String, String>? jsonPointers,
    this.budget,
    this.allowLoopbackHttp = false,
  }) : jsonPointers = jsonPointers ?? <String, String>{};

  String id;
  String name;
  ProviderKind kind;
  bool enabled;
  String executable;
  String baseUrl;
  String encryptedApiKey;
  String encryptedCloudKey;
  String usagePath;
  String balancePath;
  final Map<String, String> jsonPointers;
  String? budget;
  bool allowLoopbackHttp;

  ProviderConfig copy() => ProviderConfig(
        id: id,
        name: name,
        kind: kind,
        enabled: enabled,
        executable: executable,
        baseUrl: baseUrl,
        encryptedApiKey: encryptedApiKey,
        encryptedCloudKey: encryptedCloudKey,
        usagePath: usagePath,
        balancePath: balancePath,
        jsonPointers: Map.of(jsonPointers),
        budget: budget,
        allowLoopbackHttp: allowLoopbackHttp,
      );

  @override
  bool operator ==(Object other) =>
      other is ProviderConfig &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.enabled == enabled &&
      other.executable == executable &&
      other.baseUrl == baseUrl &&
      other.encryptedApiKey == encryptedApiKey &&
      other.encryptedCloudKey == encryptedCloudKey &&
      other.usagePath == usagePath &&
      other.balancePath == balancePath &&
      _mapEquals(other.jsonPointers, jsonPointers) &&
      other.budget == budget &&
      other.allowLoopbackHttp == allowLoopbackHttp;

  @override
  int get hashCode => Object.hash(id, name, kind, enabled, executable, baseUrl, encryptedApiKey,
      encryptedCloudKey, usagePath, balancePath, Object.hashAllUnordered(jsonPointers.entries), budget, allowLoopbackHttp);

  @override
  String toString() => 'ProviderConfig($id, $name, ${kind.wire}, enabled: $enabled)';
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// Defaults applied when a provider of [kind] is created.
class ProviderKindDefaults {
  ProviderKindDefaults({this.baseUrl = '', this.balancePath = '', this.allowLoopbackHttp = false});

  final String baseUrl;
  final String balancePath;
  final bool allowLoopbackHttp;
}

/// Root settings document matching settings.json.
class Settings {
  Settings({
    this.schemaVersion = 1,
    this.refreshMinutes = 5,
    this.alwaysOnTop = false,
    OverlaySettings? overlay,
    List<ProviderConfig>? providers,
  })  : overlay = overlay ?? OverlaySettings(),
        providers = providers ?? <ProviderConfig>[];

  int schemaVersion;
  int refreshMinutes;
  bool alwaysOnTop;
  OverlaySettings overlay;
  final List<ProviderConfig> providers;

  Settings copy() => Settings(
        schemaVersion: schemaVersion,
        refreshMinutes: refreshMinutes,
        alwaysOnTop: alwaysOnTop,
        overlay: overlay.copy(),
        providers: [for (final provider in providers) provider.copy()],
      );

  @override
  bool operator ==(Object other) =>
      other is Settings &&
      other.schemaVersion == schemaVersion &&
      other.refreshMinutes == refreshMinutes &&
      other.alwaysOnTop == alwaysOnTop &&
      other.overlay == overlay &&
      _listEquals(other.providers, providers);

  @override
  int get hashCode => Object.hash(schemaVersion, refreshMinutes, alwaysOnTop, overlay,
      Object.hashAllUnordered(providers.map((p) => p.hashCode)));
}

bool _listEquals(List<ProviderConfig> a, List<ProviderConfig> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Resolved data location for settings and cache files.
class DataPaths {
  DataPaths({required this.root, required this.settings, required this.cache, this.portable = true});

  final String root;
  final String settings;
  final String cache;
  final bool portable;
}

/// Result of loading settings, including backup recovery reporting.
class LoadSettingsResult {
  LoadSettingsResult({required this.settings, this.recoveredBackup = false, this.warning = ''});

  final Settings settings;
  final bool recoveredBackup;
  final String warning;
}