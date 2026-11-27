/// Strict settings and cache JSON codec, ported from the C++ reference.
///
/// Field allow-lists, required fields, serialization order, error messages and
/// the 2-space indent are the cross-application contract; unknown or missing
/// fields are rejected exactly as the reference does.
library;

import 'dart:convert';

import '../domain/model.dart';
import '../domain/overlay_types.dart';
import 'settings.dart';

Never _fail(String message) => throw const FormatException('settings parse failed');

String _stringFromMap(Map<String, dynamic> map, String key, String context) {
  final value = map[key];
  if (value is String) return value;
  _fail('$context field must be a string');
}

bool _boolFromMap(Map<String, dynamic> map, String key, String context) {
  final value = map[key];
  if (value is bool) return value;
  _fail('$context field must be a boolean');
}

int _intFromMap(Map<String, dynamic> map, String key, String context) {
  final value = map[key];
  if (value is int) return value;
  _fail('$context field must be an integer');
}

/// Validates allowed and required fields exactly like the reference's
/// `ValidateObject`.
void validateObject(
  Map<String, dynamic> value,
  String context,
  List<String> allowed, [
  List<String> required = const [],
]) {
  for (final key in value.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('$context contains unknown field: $key');
    }
  }
  for (final field in required) {
    if (!value.containsKey(field)) {
      throw FormatException('$context is missing field: $field');
    }
  }
}

/// Parses an overlay corner with the reference's fallback to `top-right`.
OverlayCorner parseOverlayCorner(Object? value) {
  if (value is OverlayCorner) return value;
  if (value is! String) return OverlayCorner.topRight;
  return OverlayCorner.parse(value);
}

OverlaySettings overlayFromJson(Object? raw, {int Function(int)? normalizeOpacity, int Function(int)? normalizeMargin}) {
  final overlay = OverlaySettings();
  if (raw is! Map<String, dynamic>) return overlay;
  final value = raw;
  if (value['enabled'] is bool) overlay.enabled = value['enabled'] as bool;
  if (value['visible'] is bool) overlay.visible = value['visible'] as bool;
  if (value['opacity'] is int) {
    overlay.opacity = normalizeOpacity != null ? normalizeOpacity(value['opacity'] as int) : value['opacity'] as int;
  }
  if (value['locked'] is bool) overlay.locked = value['locked'] as bool;
  if (value.containsKey('corner')) overlay.corner = parseOverlayCorner(value['corner']);
  if (value['monitor'] is String) {
    final monitor = value['monitor'] as String;
    var tooLong = monitor.length > 256;
    var hasControl = false;
    for (final code in monitor.codeUnits) {
      if (code < 0x20) {
        hasControl = true;
        break;
      }
    }
    overlay.monitor = tooLong || hasControl ? '' : monitor;
  }
  if (value['margin'] is int) {
    overlay.margin = normalizeMargin != null ? normalizeMargin(value['margin'] as int) : value['margin'] as int;
  }
  if (value['suppressFullscreen'] is bool) overlay.suppressFullscreen = value['suppressFullscreen'] as bool;
  return overlay;
}

Map<String, dynamic> overlayToJson(OverlaySettings overlay, {int Function(int)? normalizeOpacity, int Function(int)? normalizeMargin}) => {
      'enabled': overlay.enabled,
      'visible': overlay.visible,
      'opacity': normalizeOpacity != null ? normalizeOpacity(overlay.opacity) : overlay.opacity,
      'locked': overlay.locked,
      'corner': overlay.corner.wire,
      'monitor': overlay.monitor,
      'margin': normalizeMargin != null ? normalizeMargin(overlay.margin) : overlay.margin,
      'suppressFullscreen': overlay.suppressFullscreen,
    };

Map<String, dynamic> _providerToJson(ProviderConfig provider, bool redact) => {
      'id': provider.id,
      'name': provider.name,
      'kind': provider.kind.wire,
      'enabled': provider.enabled,
      'executable': provider.executable,
      'baseUrl': provider.baseUrl,
      'encryptedApiKey':
          redact && provider.encryptedApiKey.isNotEmpty ? '<protected>' : provider.encryptedApiKey,
      'encryptedCloudKey':
          redact && provider.encryptedCloudKey.isNotEmpty ? '<protected>' : provider.encryptedCloudKey,
      'usagePath': provider.usagePath,
      'balancePath': provider.balancePath,
      'jsonPointers': Map.of(provider.jsonPointers),
      if (provider.budget != null) 'budget': provider.budget,
      'allowLoopbackHttp': provider.allowLoopbackHttp,
    };

ProviderConfig providerFromJson(Object? raw) {
  if (raw is! Map<String, dynamic>) _fail('provider must be an object');
  final value = raw;
  validateObject(
    value,
    'provider',
    ['id', 'name', 'kind', 'enabled', 'executable', 'baseUrl', 'encryptedApiKey', 'encryptedCloudKey',
     'usagePath', 'balancePath', 'jsonPointers', 'budget', 'claudeBridge', 'allowLoopbackHttp'],
    ['id', 'name', 'kind'],
  );
  final provider = ProviderConfig();
  provider.id = _stringFromMap(value, 'id', 'provider');
  provider.name = _stringFromMap(value, 'name', 'provider');
  final kindText = _stringFromMap(value, 'kind', 'provider');
  try {
    provider.kind = ProviderKind.parse(kindText);
  } on ArgumentError {
    throw FormatException('unknown provider kind');
  }
  provider.enabled = value.containsKey('enabled') ? _boolFromMap(value, 'enabled', 'provider') : false;
  provider.executable = value.containsKey('executable') ? _stringFromMap(value, 'executable', 'provider') : '';
  provider.baseUrl = value.containsKey('baseUrl') ? _stringFromMap(value, 'baseUrl', 'provider') : '';
  provider.encryptedApiKey =
      value.containsKey('encryptedApiKey') ? _stringFromMap(value, 'encryptedApiKey', 'provider') : '';
  provider.encryptedCloudKey =
      value.containsKey('encryptedCloudKey') ? _stringFromMap(value, 'encryptedCloudKey', 'provider') : '';
  provider.usagePath = value.containsKey('usagePath') ? _stringFromMap(value, 'usagePath', 'provider') : '';
  provider.balancePath = value.containsKey('balancePath') ? _stringFromMap(value, 'balancePath', 'provider') : '';
  if (value.containsKey('jsonPointers')) {
    final pointers = value['jsonPointers'];
    if (pointers is! Map<String, dynamic>) _fail('provider jsonPointers must be an object');
    pointers.forEach((key, pointer) {
      if (pointer is! String) _fail('provider jsonPointers must map to strings');
      provider.jsonPointers[key] = pointer;
    });
  }
  if (value.containsKey('budget') && value['budget'] is String) {
    provider.budget = value['budget'] as String;
  }
  provider.allowLoopbackHttp =
      value.containsKey('allowLoopbackHttp') ? _boolFromMap(value, 'allowLoopbackHttp', 'provider') : false;
  return provider;
}

/// Optional [validate] hook lets the caller apply `ValidateSettings` exactly
/// like the reference's `SettingsFromJson`.
Settings settingsFromJson(Object? raw, {Settings Function(Settings)? validate}) {
  if (raw is! Map<String, dynamic>) _fail('settings must be an object');
  final value = raw;
  validateObject(
    value,
    'settings',
    ['schemaVersion', 'refreshMinutes', 'alwaysOnTop', 'overlay', 'providers'],
    ['schemaVersion'],
  );
  final settings = Settings();
  settings.schemaVersion = _intFromMap(value, 'schemaVersion', 'settings');
  settings.refreshMinutes = value.containsKey('refreshMinutes') ? _intFromMap(value, 'refreshMinutes', 'settings') : 5;
  settings.alwaysOnTop = value.containsKey('alwaysOnTop') ? _boolFromMap(value, 'alwaysOnTop', 'settings') : false;
  if (value.containsKey('overlay')) settings.overlay = overlayFromJson(value['overlay']);
  final providers = value.containsKey('providers') ? value['providers'] : <Object?>[];
  if (providers is! List) _fail('settings providers must be an array');
  for (final provider in providers) {
    settings.providers.add(providerFromJson(provider));
  }
  if (validate != null) {
    return validate(settings);
  }
  return settings;
}

Map<String, dynamic> settingsToJson(Settings settings, bool redact) => {
      'schemaVersion': settings.schemaVersion,
      'refreshMinutes': settings.refreshMinutes,
      'alwaysOnTop': settings.alwaysOnTop,
      'overlay': overlayToJson(settings.overlay),
      'providers': [for (final provider in settings.providers) _providerToJson(provider, redact)],
    };

/// Serializes settings with a 2-space indent like the reference's `dump(2)`.
/// nlohmann::json stores objects in a sorted map, so the encoder sorts keys
/// recursively to produce byte-identical documents.
String encodeSettings(Settings settings, {bool redact = false}) =>
    const JsonEncoder.withIndent('  ').convert(_sorted(settingsToJson(settings, redact)));

Object? _sorted(Object? value) {
  if (value is Map<String, dynamic>) {
    final sorted = <String, dynamic>{};
    for (final key in value.keys.toList()..sort()) {
      sorted[key] = _sorted(value[key]);
    }
    return sorted;
  }
  if (value is List) {
    return [for (final entry in value) _sorted(entry)];
  }
  return value;
}

/// Serializes the redacted export with the `<protected>` marker.
String redactedSettingsJson(Settings settings) => encodeSettings(settings, redact: true);

int _unixSeconds(DateTime value) => (value.toUtc().millisecondsSinceEpoch ~/ 1000);

DateTime _fromUnix(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

Map<String, dynamic> _metricToJson(Metric metric) => {
      'kind': metric.kind.wire,
      'value': metric.value,
      'unit': metric.unit.wire,
      'scope': metric.scope.wire,
      'provenance': metric.provenance.wire,
      'availability': metric.availability.wire,
      'label': metric.label,
      if (metric.resetsAt != null) 'resetsAt': _unixSeconds(metric.resetsAt!),
      if (metric.window != null) 'windowSeconds': metric.window!.inSeconds,
    };

Metric metricFromJson(Object? raw) {
  if (raw is! Map<String, dynamic>) _fail('metric must be an object');
  final value = raw;
  validateObject(
    value,
    'metric',
    ['kind', 'value', 'unit', 'scope', 'provenance', 'availability', 'label', 'resetsAt', 'windowSeconds'],
    ['kind', 'unit', 'scope', 'provenance', 'availability'],
  );
  final metric = Metric();
  try {
    metric.kind = MetricKind.parse(_stringFromMap(value, 'kind', 'metric'));
    metric.unit = MetricUnit.parse(_stringFromMap(value, 'unit', 'metric'));
    metric.scope = MetricScope.parse(_stringFromMap(value, 'scope', 'metric'));
    metric.provenance = Provenance.parse(_stringFromMap(value, 'provenance', 'metric'));
    metric.availability = Availability.parse(_stringFromMap(value, 'availability', 'metric'));
  } on ArgumentError {
    throw FormatException('unknown metric enum value');
  }
  metric.value = value.containsKey('value') ? _stringFromMap(value, 'value', 'metric') : '';
  metric.label = value.containsKey('label') ? _stringFromMap(value, 'label', 'metric') : '';
  if (value.containsKey('resetsAt')) {
    final resets = value['resetsAt'];
    if (resets is! int) _fail('metric resetsAt must be an integer');
    metric.resetsAt = _fromUnix(resets);
  }
  if (value.containsKey('windowSeconds')) {
    final window = value['windowSeconds'];
    if (window is! int) _fail('metric windowSeconds must be an integer');
    metric.window = Duration(seconds: window);
  }
  return metric;
}

Map<String, dynamic> snapshotToJson(ProviderSnapshot snapshot) => {
      'providerId': snapshot.providerId,
      'displayName': snapshot.displayName,
      'kind': snapshot.kind.wire,
      'observedAt': _unixSeconds(snapshot.observedAt),
      'freshness': snapshot.freshness.wire,
      'health': snapshot.health.wire,
      'metrics': [for (final metric in snapshot.metrics) _metricToJson(metric)],
      'accountLabel': snapshot.accountLabel,
      if (snapshot.error != null)
        'error': {
          'code': snapshot.error!.code,
          'message': snapshot.error!.message,
          'transient': snapshot.error!.transient,
          if (snapshot.error!.retryAfter != null) 'retryAfter': snapshot.error!.retryAfter!.inSeconds,
        },
    };

ProviderSnapshot snapshotFromJson(Object? raw) {
  if (raw is! Map<String, dynamic>) _fail('snapshot must be an object');
  final value = raw;
  validateObject(
    value,
    'snapshot',
    ['providerId', 'displayName', 'kind', 'observedAt', 'freshness', 'health', 'metrics', 'error',
     'accountLabel'],
    ['providerId', 'displayName', 'kind', 'observedAt', 'freshness', 'health'],
  );
  final snapshot = ProviderSnapshot();
  snapshot.providerId = _stringFromMap(value, 'providerId', 'snapshot');
  snapshot.displayName = _stringFromMap(value, 'displayName', 'snapshot');
  final kindText = _stringFromMap(value, 'kind', 'snapshot');
  try {
    snapshot.kind = ProviderKind.parse(kindText);
    snapshot.freshness = Freshness.parse(_stringFromMap(value, 'freshness', 'snapshot'));
    snapshot.health = Health.parse(_stringFromMap(value, 'health', 'snapshot'));
  } on ArgumentError {
    throw FormatException('unknown snapshot enum value');
  }
  snapshot.observedAt = _fromUnix(_intFromMap(value, 'observedAt', 'snapshot'));
  snapshot.accountLabel = value.containsKey('accountLabel') ? _stringFromMap(value, 'accountLabel', 'snapshot') : '';
  final metrics = value.containsKey('metrics') ? value['metrics'] : <Object?>[];
  if (metrics is! List) _fail('snapshot metrics must be an array');
  for (final metric in metrics) {
    snapshot.metrics.add(metricFromJson(metric));
  }
  if (value.containsKey('error')) {
    final error = value['error'];
    if (error is! Map<String, dynamic>) _fail('snapshot error must be an object');
    validateObject(error, 'provider error', ['code', 'message', 'transient', 'retryAfter']);
    final parsed = ProviderError(
      error.containsKey('code') ? _stringFromMap(error, 'code', 'provider error') : 'cached-error',
      error.containsKey('message') ? _stringFromMap(error, 'message', 'provider error') : '',
      transient: error.containsKey('transient') ? _boolFromMap(error, 'transient', 'provider error') : false,
    );
    if (error.containsKey('retryAfter')) {
      final retry = error['retryAfter'];
      if (retry is! int) _fail('provider error retryAfter must be an integer');
      parsed.retryAfter = Duration(seconds: retry);
    }
    snapshot.error = parsed;
  }
  return snapshot;
}

/// Encodes snapshots for cache.json with the reference's filtering of invalid
/// or metric-less snapshots applied by the caller.
String encodeCache(List<ProviderSnapshot> snapshots) =>
    const JsonEncoder.withIndent('  ').convert(_sorted({
      'schemaVersion': 1,
      'snapshots': [for (final snapshot in snapshots) snapshotToJson(snapshot)],
    }));

/// Decodes cache.json, applying the reference's load downgrade: freshness
/// forced stale, healthy health downgraded to partial.
List<ProviderSnapshot> cacheFromJson(Object? raw) {
  if (raw is! Map<String, dynamic>) _fail('cache must be an object');
  final value = raw;
  validateObject(value, 'cache', ['schemaVersion', 'snapshots'], ['schemaVersion']);
  if (_intFromMap(value, 'schemaVersion', 'cache') != 1) {
    throw const FormatException('unsupported cache schema');
  }
  final snapshots = value.containsKey('snapshots') ? value['snapshots'] : <Object?>[];
  if (snapshots is! List) _fail('cache snapshots must be an array');
  return [
    for (final entry in snapshots)
      () {
        final snapshot = snapshotFromJson(entry);
        snapshot.freshness = Freshness.stale;
        if (snapshot.health == Health.healthy) snapshot.health = Health.partial;
        return snapshot;
      }(),
  ];
}

/// Decodes a JSON document, rethrowing parse failures with the reference's
/// flat error surface.
dynamic decodeJson(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    rethrow;
  }
}