import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_usage_monitor/config/config.dart';
import 'package:ai_usage_monitor/domain/domain.dart';
import 'package:ai_usage_monitor/domain/overlay_types.dart';

void main() {
  group('settings JSON round trip', () {
    test('default settings encode with reference shape', () {
      // nlohmann::json sorts object keys, so the byte-parity encoder emits
      // sorted keys.
      final text = encodeSettings(Settings());
      expect(text, '''{
  "alwaysOnTop": false,
  "overlay": {
    "corner": "top-right",
    "enabled": false,
    "locked": true,
    "margin": 12,
    "monitor": "",
    "opacity": 78,
    "suppressFullscreen": false,
    "visible": true
  },
  "providers": [],
  "refreshMinutes": 5,
  "schemaVersion": 1
}''');
    });

    test('round trip preserves all fields', () {
      final settings = Settings(
        schemaVersion: 1,
        refreshMinutes: 12,
        alwaysOnTop: true,
        overlay: OverlaySettings(
          enabled: true,
          visible: false,
          opacity: 90,
          locked: false,
          corner: OverlayCorner.bottomLeft,
          monitor: r'\\.\DISPLAY1',
          margin: 40,
          suppressFullscreen: true,
        ),
        providers: [
          ProviderConfig(
            id: 'codex',
            name: 'Codex',
            kind: ProviderKind.codex,
            enabled: true,
            executable: 'codex',
          ),
          ProviderConfig(
            id: 'deepseek',
            name: 'DeepSeek',
            kind: ProviderKind.deepSeek,
            baseUrl: 'https://api.deepseek.com',
            balancePath: '/user/balance',
            encryptedApiKey: 'dpapi:AAA',
            budget: '20.00',
          ),
          ProviderConfig(
            id: 'generic',
            name: 'Generic',
            kind: ProviderKind.openAiCompatible,
            baseUrl: 'https://example.com',
            usagePath: '/usage',
            balancePath: '/balance',
            jsonPointers: {'used_percent': '/usage/percent', 'total_tokens': '/usage/tokens'},
            allowLoopbackHttp: false,
          ),
        ],
      );
      final decoded = settingsFromJson(decodeJson(encodeSettings(settings)));
      expect(decoded, settings);
    });

    test('rejects unknown fields', () {
      expect(
        () => settingsFromJson(decodeJson('{"schemaVersion":1,"bogus":1}')),
        throwsFormatException,
      );
      expect(
        () => providerFromJson(decodeJson('{"id":"a","name":"A","kind":"codex","extra":true}')),
        throwsFormatException,
      );
      expect(
        () => metricFromJson(decodeJson('{"kind":"used-percent","unit":"percent","scope":"day",'
            '"provenance":"derived","availability":"available","wat":1}')),
        throwsFormatException,
      );
    });

    test('rejects missing required fields', () {
      expect(() => settingsFromJson(decodeJson('{}')), throwsFormatException);
      expect(
        () => providerFromJson(decodeJson('{"id":"a","kind":"codex"}')),
        throwsFormatException,
      );
    });

    test('rejects unknown provider kind and metric enums', () {
      expect(
        () => providerFromJson(decodeJson('{"id":"a","name":"A","kind":"other"}')),
        throwsFormatException,
      );
      expect(
        () => metricFromJson(decodeJson(
            '{"kind":"nope","unit":"percent","scope":"day","provenance":"derived","availability":"available"}')),
        throwsFormatException,
      );
    });

    test('snapshot and cache round trips', () {
      final snapshot = ProviderSnapshot(
        providerId: 'p1',
        displayName: 'P1',
        kind: ProviderKind.ollama,
        observedAt: DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true),
        freshness: Freshness.fresh,
        health: Health.healthy,
        accountLabel: 'account@example.com',
        metrics: [
          Metric(
            kind: MetricKind.usedPercent,
            value: '25',
            unit: MetricUnit.percent,
            scope: MetricScope.rollingWindow,
            resetsAt: DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true),
            window: const Duration(minutes: 300),
            label: 'Codex principal usado',
          ),
          Metric(
            kind: MetricKind.balance,
            value: '42.50',
            unit: MetricUnit.usd,
            scope: MetricScope.currentBalance,
            label: 'Saldo USD',
          ),
        ],
        error: ProviderError('refreshing', 'Actualizando…', transient: true, retryAfter: const Duration(seconds: 30)),
      );
      final decoded = snapshotFromJson(decodeJson(jsonEncode(snapshotToJson(snapshot))));
      expect(decoded.providerId, snapshot.providerId);
      expect(decoded.displayName, snapshot.displayName);
      expect(decoded.kind, snapshot.kind);
      expect(decoded.observedAt, snapshot.observedAt);
      expect(decoded.freshness, snapshot.freshness);
      expect(decoded.health, snapshot.health);
      expect(decoded.accountLabel, snapshot.accountLabel);
      expect(decoded.metrics, snapshot.metrics);
      expect(decoded.error, snapshot.error);
    });

    test('cache load downgrades freshness and health', () {
      final cache = encodeCache([
        ProviderSnapshot(
          providerId: 'p1',
          displayName: 'P1',
          observedAt: DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true),
          freshness: Freshness.fresh,
          health: Health.healthy,
        ),
      ]);
      final loaded = cacheFromJson(decodeJson(cache));
      expect(loaded.single.freshness, Freshness.stale);
      expect(loaded.single.health, Health.partial);
    });

    test('cache rejects unsupported schema', () {
      expect(
        () => cacheFromJson(decodeJson('{"schemaVersion":2,"snapshots":[]}')),
        throwsFormatException,
      );
    });
  });

  group('validateSettings', () {
    test('accepts defaults', () {
      expect(validateSettings(Settings()), isNull);
    });

    test('rejects schema version changes', () {
      expect(validateSettings(Settings(schemaVersion: 2)), 'unsupported settings schema');
    });

    test('rejects interval outside 1..60', () {
      expect(validateSettings(Settings(refreshMinutes: 0)), 'refreshMinutes must be between 1 and 60');
      expect(validateSettings(Settings(refreshMinutes: 61)), 'refreshMinutes must be between 1 and 60');
    });

    test('rejects opacity and margin outside bounds', () {
      expect(
        validateSettings(Settings(overlay: OverlaySettings(opacity: 49))),
        'overlay opacity must be between 50 and 100',
      );
      expect(
        validateSettings(Settings(overlay: OverlaySettings(margin: -1))),
        'overlay margin must be between 0 and 96',
      );
    });

    test('rejects long monitor identifiers', () {
      expect(
        validateSettings(Settings(overlay: OverlaySettings(monitor: 'x' * 257))),
        'overlay monitor identifier is too long',
      );
    });

    test('requires provider id and name', () {
      final settings = Settings(providers: [ProviderConfig(id: '', name: '')]);
      expect(validateSettings(settings), 'provider id and name are required');
    });

    test('requires Ollama base URL', () {
      final settings = Settings(
        providers: [ProviderConfig(id: 'a', name: 'A', kind: ProviderKind.ollama)],
      );
      expect(validateSettings(settings), 'provider base URL is required for Ollama');
    });

    test('rejects invalid budget', () {
      final settings = Settings(
        providers: [ProviderConfig(id: 'a', name: 'A', budget: '-1')],
      );
      expect(validateSettings(settings), 'provider budget must be a non-negative decimal');
      expect(
        validateSettings(Settings(providers: [ProviderConfig(id: 'a', name: 'A', budget: 'abc')])),
        'provider budget must be a non-negative decimal',
      );
    });

    test('cloud credentials are Ollama-only', () {
      final settings = Settings(
        providers: [ProviderConfig(id: 'a', name: 'A', encryptedCloudKey: 'dpapi:AA')],
      );
      expect(validateSettings(settings), 'cloud credentials are only used by the Ollama provider');
    });

    test('routes must be bounded same-origin paths', () {
      expect(
        validateSettings(Settings(providers: [ProviderConfig(id: 'a', name: 'A', usagePath: 'http://x')])),
        "provider routes must be bounded same-origin paths beginning with '/'",
      );
      expect(
        validateSettings(Settings(providers: [ProviderConfig(id: 'a', name: 'A', usagePath: 'usage')])),
        "provider routes must be bounded same-origin paths beginning with '/'",
      );
      expect(
        validateSettings(Settings(providers: [ProviderConfig(id: 'a', name: 'A', usagePath: '/' * 2049)])),
        "provider routes must be bounded same-origin paths beginning with '/'",
      );
    });

    test('limits JSON Pointer mappings', () {
      final pointers = {for (var i = 0; i < 17; i++) 'k$i': '/v$i'};
      expect(
        validateSettings(
          Settings(providers: [ProviderConfig(id: 'a', name: 'A', jsonPointers: pointers)]),
        ),
        'a provider may define at most 16 JSON Pointer mappings',
      );
    });

    test('validates JSON Pointer syntax', () {
      expect(
        validateSettings(
          Settings(
            providers: [
              ProviderConfig(id: 'a', name: 'A', jsonPointers: {'used_percent': 'used'}),
            ],
          ),
        ),
        'invalid JSON Pointer mapping',
      );
      expect(
        validateSettings(
          Settings(
            providers: [
              ProviderConfig(id: 'a', name: 'A', jsonPointers: {'used_percent': '/used/percent'}),
            ],
          ),
        ),
        isNull,
      );
    });
  });

  group('overlay normalization', () {
    test('opacity clamps to 50..100', () {
      expect(normalizeOverlayOpacity(0), 50);
      expect(normalizeOverlayOpacity(49), 50);
      expect(normalizeOverlayOpacity(78), 78);
      expect(normalizeOverlayOpacity(120), 100);
      expect(normalizeOverlayOpacity(101), 100);
    });

    test('margin clamps to 0..96', () {
      expect(normalizeOverlayMargin(-5), 0);
      expect(normalizeOverlayMargin(12), 12);
      expect(normalizeOverlayMargin(200), 96);
    });

    test('corner falls back to top-right', () {
      expect(parseOverlayCorner('top-left'), OverlayCorner.topLeft);
      expect(parseOverlayCorner('bottom-right'), OverlayCorner.bottomRight);
      expect(parseOverlayCorner('other'), OverlayCorner.topRight);
      expect(parseOverlayCorner(42), OverlayCorner.topRight);
    });

    test('monitor is cleared when too long or control-charactered', () {
      final long = overlayFromJson({
        'monitor': 'x' * 257,
        'opacity': 78,
      });
      expect(long.monitor, '');
      final control = overlayFromJson({
        'monitor': 'bad\x01name',
        'opacity': 78,
      });
      expect(control.monitor, '');
      final clean = overlayFromJson({
        'monitor': r'\\.\DISPLAY1',
        'opacity': 78,
      });
      expect(clean.monitor, r'\\.\DISPLAY1');
    });

    test('opacity and margin are normalized on decode', () {
      final overlay = overlayFromJson(
        {'opacity': 30, 'margin': 200},
        normalizeOpacity: normalizeOverlayOpacity,
        normalizeMargin: normalizeOverlayMargin,
      );
      expect(overlay.opacity, 50);
      expect(overlay.margin, 96);
    });

    test('non-object overlay yields defaults', () {
      final overlay = overlayFromJson('nope');
      expect(overlay, OverlaySettings());
    });
  });

  group('per-kind defaults', () {
    test('deepseek defaults', () {
      final defaults = defaultsForKind(ProviderKind.deepSeek);
      expect(defaults.baseUrl, 'https://api.deepseek.com');
      expect(defaults.balancePath, '/user/balance');
      expect(defaults.allowLoopbackHttp, isFalse);
    });

    test('ollama defaults', () {
      final defaults = defaultsForKind(ProviderKind.ollama);
      expect(defaults.baseUrl, 'http://localhost:11434');
      expect(defaults.allowLoopbackHttp, isTrue);
      expect(defaults.balancePath, '');
    });

    test('codex, claude and openai-compatible are empty', () {
      for (final kind in [ProviderKind.codex, ProviderKind.claudeSubscription, ProviderKind.openAiCompatible]) {
        final defaults = defaultsForKind(kind);
        expect(defaults.baseUrl, '');
        expect(defaults.balancePath, '');
        expect(defaults.allowLoopbackHttp, isFalse);
      }
    });
  });

  group('atomic writes and backup recovery', () {
    late Directory root;
    late DataPaths paths;

    setUp(() {
      root = Directory.systemTemp.createTempSync('ai_usage_config_test');
      final separator = Platform.pathSeparator;
      paths = DataPaths(
        root: root.path,
        settings: '${root.path}${separator}settings.json',
        cache: '${root.path}${separator}cache.json',
      );
    });

    tearDown(() {
      root.deleteSync(recursive: true);
    });

    test('write rotates previous file to .bak', () {
      saveSettings(paths, Settings(refreshMinutes: 5));
      saveSettings(paths, Settings(refreshMinutes: 10));
      expect(File('${paths.settings}.bak').existsSync(), isTrue);
      expect(
        (decodeJson(File(paths.settings).readAsStringSync()) as Map)['refreshMinutes'],
        10,
      );
      expect(
        (decodeJson(File('${paths.settings}.bak').readAsStringSync()) as Map)['refreshMinutes'],
        5,
      );
    });

    test('load recovers from .bak after primary corruption', () {
      saveSettings(paths, Settings(refreshMinutes: 5));
      saveSettings(paths, Settings(refreshMinutes: 7));
      File(paths.settings).writeAsStringSync('{"schemaVersion":1,');
      final result = loadSettings(paths);
      expect(result.recoveredBackup, isTrue);
      expect(result.settings.refreshMinutes, 5);
      expect(result.warning, contains('Recovered settings backup after:'));
    });

    test('load fails through when no backup exists', () {
      File(paths.settings).writeAsStringSync('{bad json');
      expect(() => loadSettings(paths), throwsException);
    });

    test('save rejects invalid settings', () {
      expect(
        () => saveSettings(paths, Settings(refreshMinutes: 0)),
        throwsFormatException,
      );
    });

    test('cache load falls back to .bak then empty', () {
      expect(loadCache(paths), isEmpty);
      saveCache(paths, []);
      expect(loadCache(paths), isEmpty);
      File(paths.cache).writeAsStringSync('{bad');
      expect(loadCache(paths), isEmpty);
    });

    test('saveCache filters invalid snapshots', () {
      final invalid = ProviderSnapshot(
        providerId: '',
        displayName: '',
        observedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      saveCache(paths, [invalid]);
      expect(loadCache(paths), isEmpty);
    });

    test('atomicWrite failure keeps previous content', () {
      final target = File('${root.path}${Platform.pathSeparator}file.json');
      target.writeAsStringSync('first');
      atomicWrite(target.path, 'second');
      expect(target.readAsStringSync(), 'second');
      expect(File('${target.path}.bak').readAsStringSync(), 'first');
    });
  });

  group('redaction', () {
    test('redactedSettingsJson replaces protected tokens', () {
      final settings = Settings(
        providers: [
          ProviderConfig(
            id: 'a',
            name: 'A',
            kind: ProviderKind.ollama,
            baseUrl: 'http://localhost:11434',
            encryptedApiKey: 'secret-service:abcd',
            encryptedCloudKey: 'session:ef01',
          ),
        ],
      );
      final redacted = redactedSettingsJson(settings);
      expect(redacted, isNot(contains('secret-service:abcd')));
      expect(redacted, contains('"<protected>"'));
      final plain = encodeSettings(settings);
      expect(plain, contains('secret-service:abcd'));
      expect(plain, contains('session:ef01'));
    });
  });

  group('portable executable references', () {
    test('keeps configured path when discovery differs', () {
      expect(makeExecutableReferencePortable('codex', '/other/codex', '/bin/codex'), '/other/codex');
    });

    test('uses command when configured equals discovered', () {
      final temp = Directory.systemTemp.createTempSync('portable');
      addTearDown(() => temp.deleteSync(recursive: true));
      final exe = File('${temp.path}${Platform.pathSeparator}codex')..writeAsStringSync('');
      final result = makeExecutableReferencePortable('codex', exe.path, exe.path);
      expect(result, 'codex');
    });
  });

  group('data paths', () {
    test('environment override wins and is non-portable', () {
      final temp = Directory.systemTemp.createTempSync('data_override');
      addTearDown(() => temp.deleteSync(recursive: true));
      // resolveDataPaths reads the environment directly; the per-user fallback
      // injection exercises precedence without mutating process env.
      final paths = resolveDataPaths('${temp.path}${Platform.pathSeparator}app', perUserRoot: () => temp.path);
      expect(paths.portable, isTrue);
      expect(paths.settings, endsWith('settings.json'));
    });
  });
}