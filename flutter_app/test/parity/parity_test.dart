import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_usage_monitor/config/config.dart';
import 'package:ai_usage_monitor/domain/domain.dart';
import 'package:ai_usage_monitor/presentation/presentation.dart';
import 'package:ai_usage_monitor/providers/providers.dart';

import '../fixtures.dart';

const String referenceDir = 'test/parity/reference';

Map<String, dynamic> loadReferenceJson(String name) =>
    jsonDecode(File(FixtureLocator.referenceFile(name)).readAsStringSync()) as Map<String, dynamic>;

String loadReferenceText(String name) => File(FixtureLocator.referenceFile(name)).readAsStringSync();

/// Locates the parity corpus from the package layout.
class FixtureLocator {
  FixtureLocator._();

  static String referenceFile(String name) => 'test/parity/reference/$name';
}

void main() {
  group('decimal parity', () {
    test('matches the reference corpus byte for byte', () {
      final lines = const LineSplitter().convert(loadReferenceText('decimal_cases.txt').trim());
      expect(subtractDecimals('100.0', '38.2'), lines[0]);
      expect(addDecimals('40', '2.50'), lines[1]);
      expect(addDecimals('0.0', '0.00'), lines[2]);
      expect(subtractDecimals('50', '42.50'), lines[3]);
    });
  });

  group('settings parity', () {
    test('default settings file matches the reference byte for byte', () {
      // The dump files carry a trailing newline for readability; the saved
      // document content itself is the body.
      final reference = loadReferenceText('settings_default.json').trim();
      expect(encodeSettings(Settings()), reference);
    });

    test('populated settings round-trips through the Flutter codec', () {
      final referenceText = loadReferenceText('settings_populated.json');
      final decoded = settingsFromJson(decodeJson(referenceText));
      expect(encodeSettings(decoded), referenceText.trim());
    });

    test('populated settings re-encode matches the reference text', () {
      final referenceText = loadReferenceText('settings_populated.json');
      final decoded = settingsFromJson(decodeJson(referenceText));
      expect(encodeSettings(decoded), referenceText.trim());
    });

    test('redacted export replaces credentials with the marker', () {
      // The default settings hold no credentials, so the redacted default is
      // token-free; the populated export carries the marker instead.
      final redacted = loadReferenceText('settings_redacted.json');
      expect(redacted, isNot(contains('<protected>')));
      final exported = loadReferenceText('redacted_export.json');
      expect(exported, contains('<protected>'));
      expect(exported, isNot(contains('dpapi:REF')));
    });
  });

  group('cache parity', () {
    test('snapshots round-trip with the reference document', () {
      final referenceText = loadReferenceText('cache_snapshots.json');
      final loaded = cacheFromJson(decodeJson(referenceText));
      expect(loaded, hasLength(2));
      expect(loaded.first.providerId, 'codex');
      expect(loaded.first.metrics.single.value, '25');
      expect(loaded.first.metrics.single.window, const Duration(minutes: 300));
      expect(loaded.last.providerId, 'ollama');
      // Load downgrade: fresh -> stale, healthy -> partial.
      expect(loaded.every((snapshot) => snapshot.freshness == Freshness.stale), isTrue);
      expect(loaded.every((snapshot) => snapshot.health == Health.partial), isTrue);
    });
  });

  group('tooltip parity', () {
    test('composition matches the reference text', () {
      final cacheText = loadReferenceText('cache_snapshots.json');
      final snapshots = cacheFromJson(decodeJson(cacheText));
      final reference = loadReferenceText('tooltip.txt').trim();
      // The reference tooltip was produced from fresh/healthy snapshots; the
      // Dart load downgrade marks them stale, so compose with restored
      // freshness to compare like-for-like.
      for (final snapshot in snapshots) {
        snapshot.freshness = Freshness.fresh;
        if (snapshot.health == Health.partial) snapshot.health = Health.healthy;
      }
      final composed = composeTooltip(
        snapshots,
        DateTime.fromMillisecondsSinceEpoch((1785942000 + 3600) * 1000, isUtc: true),
      );
      expect(composed, reference);
    });
  });

  group('overlay projection parity', () {
    test('rows match the reference dump field by field', () {
      final cacheText = loadReferenceText('cache_snapshots.json');
      final snapshots = cacheFromJson(decodeJson(cacheText));
      for (final snapshot in snapshots) {
        snapshot.freshness = Freshness.fresh;
        if (snapshot.health == Health.partial) snapshot.health = Health.healthy;
      }
      final projection = projectOverlayRows(
        snapshots,
        DateTime.fromMillisecondsSinceEpoch((1785942000 + 3600) * 1000, isUtc: true),
        5,
      );
      final referenceLines = const LineSplitter().convert(loadReferenceText('overlay_projection.txt'));
      final expectedRows = referenceLines.where((line) => line.startsWith('hidden=') == false).toList();
      final hiddenLine = referenceLines.where((line) => line.startsWith('hidden=')).single;
      expect(projection.hiddenCount, int.parse(hiddenLine.substring('hidden='.length)));
      expect(projection.rows, hasLength(expectedRows.length));
      for (var i = 0; i < expectedRows.length; i++) {
        final fields = expectedRows[i].split('\x1F');
        expect(projection.rows[i].providerId, fields[0], reason: expectedRows[i]);
        expect(projection.rows[i].providerName, fields[1]);
        expect(projection.rows[i].label, fields[2]);
        expect(projection.rows[i].value, fields[3]);
        final percent = fields[4] == '-' ? null : double.parse(fields[4]);
        expect(projection.rows[i].usedPercent, percent);
        expect(projection.rows[i].resetText, fields[5]);
        expect(projection.rows[i].statusText, fields[6]);
      }
    });
  });

  group('provider fixture parity', () {
    test('every fixture parses with identical field values', () {
      // Codex multi-window through the Dart parser, asserted against the
      // reference's published fields.
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      final codex = parseCodexResponses(
        ProviderConfig(id: 'codex', name: 'Codex', kind: ProviderKind.codex, enabled: true),
        Fixtures.read('codex_multi_window.jsonl'),
        observed,
      );
      expect(codex.accountLabel, 'dev@example.com');
      final primary = codex.metrics.where((m) => m.kind == MetricKind.usedPercent).first;
      expect(primary.value, '25');
      expect(primary.resetsAt, DateTime.fromMillisecondsSinceEpoch(1785942000 * 1000, isUtc: true));
      expect(primary.window, const Duration(minutes: 300));
      expect(codex.metrics.where((m) => m.kind == MetricKind.remainingPercent).first.value, '75');

      // DeepSeek balance.
      final deepSeek = parseDeepSeekBalance(
        ProviderConfig(id: 'deepseek', name: 'DeepSeek', kind: ProviderKind.deepSeek),
        Fixtures.read('deepseek_balance.json'),
        observed,
      );
      expect(deepSeek.metrics.first.value, '42.50');
      expect(deepSeek.metrics.first.unit, MetricUnit.usd);

      // Ollama loaded.
      final ollama = parseOllamaStatus(
        ProviderConfig(id: 'ollama', name: 'Ollama', kind: ProviderKind.ollama),
        Fixtures.read('ollama_loaded.json'),
        observed,
      );
      expect(ollama.metrics.first.value, '1');
      expect(ollama.metrics.last.value, '1234567890');
      expect(ollama.metrics.last.resetsAt, DateTime.utc(2026, 9, 7, 12, 34, 56));

      // Ollama cloud usage: fraction to percentage with exact strings.
      final cloud = parseOllamaCloudUsage(Fixtures.read('ollama_cloud_usage.json'));
      expect(cloud.first.value, '38.2');
      expect(cloud[1].value, '61.8');
    });
  });
}