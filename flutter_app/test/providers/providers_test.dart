import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_usage_monitor/config/config.dart';
import 'package:ai_usage_monitor/domain/domain.dart';
import 'package:ai_usage_monitor/providers/providers.dart';

import '../fixtures.dart';

ProviderConfig configOf(ProviderKind kind, {String? budget}) => ProviderConfig(
      id: 'test',
      name: 'Test',
      kind: kind,
      enabled: true,
      budget: budget,
    );

void main() {
  group('parseDeepSeekBalance (deepseek_balance.json)', () {
    test('produces per-currency balances and unsupported tokens', () {
      final json = Fixtures.read('deepseek_balance.json');
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      final snapshot = parseDeepSeekBalance(configOf(ProviderKind.deepSeek), json, observed);
      expect(snapshot.providerId, 'test');
      expect(snapshot.kind, ProviderKind.deepSeek);
      expect(snapshot.freshness, Freshness.fresh);
      expect(snapshot.health, Health.healthy);
      expect(snapshot.error, isNull);
      expect(snapshot.metrics, hasLength(3));

      final usd = snapshot.metrics[0];
      expect(usd.kind, MetricKind.balance);
      expect(usd.value, '42.50');
      expect(usd.unit, MetricUnit.usd);
      expect(usd.scope, MetricScope.currentBalance);
      expect(usd.provenance, Provenance.providerReported);
      expect(usd.availability, Availability.available);
      expect(usd.label, 'Saldo USD');

      final cny = snapshot.metrics[1];
      expect(cny.value, '110.00');
      expect(cny.unit, MetricUnit.cny);
      expect(cny.label, 'Saldo CNY');

      final tokens = snapshot.metrics[2];
      expect(tokens.kind, MetricKind.totalTokens);
      expect(tokens.availability, Availability.unsupported);
      expect(tokens.label, 'Tokens usados');
    });

    test('derived spend appears with a budget', () {
      final json = Fixtures.read('deepseek_balance.json');
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      final snapshot = parseDeepSeekBalance(configOf(ProviderKind.deepSeek, budget: '50'), json, observed);
      final spend = snapshot.metrics.where((m) => m.kind == MetricKind.spent).toList();
      // The reference derives spend for every non-unknown currency, so both
      // USD and CNY entries carry a derived metric.
      expect(spend, hasLength(2));
      expect(spend[0].value, '7.5');
      expect(spend[0].unit, MetricUnit.usd);
      expect(spend[0].provenance, Provenance.derived);
      expect(spend[0].label, 'Consumido derivado USD');
      expect(spend[1].value, '-60');
      expect(spend[1].unit, MetricUnit.cny);
      expect(spend[1].label, 'Consumido derivado CNY');
    });

    test('is_available false degrades to partial', () {
      final json = jsonDecode(Fixtures.read('deepseek_balance.json')) as Map<String, dynamic>;
      json['is_available'] = false;
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      final snapshot = parseDeepSeekBalance(configOf(ProviderKind.deepSeek), jsonEncode(json), observed);
      expect(snapshot.health, Health.partial);
      expect(snapshot.error!.code, 'balance-unavailable');
      expect(snapshot.metrics, isNotEmpty);
    });

    test('missing schema fields fail closed', () {
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      expect(
        () => parseDeepSeekBalance(configOf(ProviderKind.deepSeek), '{}', observed),
        throwsA(isA<ProviderException>()),
      );
      expect(
        () => parseDeepSeekBalance(configOf(ProviderKind.deepSeek), '{"is_available":true}', observed),
        throwsA(isA<ProviderException>()),
      );
    });
  });

  group('parseGenericMetrics (generic_usage.json)', () {
    test('configured pointers resolve in reference order', () {
      final json = Fixtures.read('generic_usage.json');
      final config = configOf(ProviderKind.openAiCompatible)
        ..baseUrl = 'https://example.com'
        ..usagePath = '/usage'
        ..jsonPointers.addAll({
          'used_percent': '/usage/used_percent',
          'total_tokens': '/usage/total_tokens',
          'balance_usd': '/billing/balance',
        });
      final metrics = parseGenericMetrics(config, json);
      expect(metrics.map((m) => m.kind), [
        MetricKind.usedPercent,
        MetricKind.totalTokens,
        MetricKind.balance,
      ]);
      expect(metrics[0].value, '33');
      expect(metrics[0].unit, MetricUnit.percent);
      expect(metrics[1].value, '9876');
      expect(metrics[1].unit, MetricUnit.tokens);
      expect(metrics[2].value, '12.75');
      expect(metrics[2].unit, MetricUnit.usd);
      expect(metrics.map((m) => m.label), ['Uso', 'Tokens', 'Saldo USD']);
    });

    test('missing pointer fails the whole refresh', () {
      final config = configOf(ProviderKind.openAiCompatible)
        ..jsonPointers.addAll({
          'used_percent': '/usage/used_percent',
          'total_tokens': '/usage/absent',
        });
      expect(
        () => parseGenericMetrics(config, Fixtures.read('generic_usage.json')),
        throwsA(
          isA<ProviderException>()
              .having((e) => e.error.code, 'code', 'missing-pointer')
              .having((e) => e.error.message, 'message', 'JSON Pointer missing for total_tokens'),
        ),
      );
    });

    test('unconfigured pointers are skipped', () {
      final metrics = parseGenericMetrics(configOf(ProviderKind.openAiCompatible), Fixtures.read('generic_usage.json'));
      expect(metrics, isEmpty);
    });
  });

  group('parseCodexResponses (codex fixtures)', () {
    test('multi-window fixture publishes account and both windows', () {
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      final snapshot = parseCodexResponses(configOf(ProviderKind.codex), Fixtures.read('codex_multi_window.jsonl'), observed);
      expect(snapshot.accountLabel, 'dev@example.com');
      expect(snapshot.kind, ProviderKind.codex);
      final used = snapshot.metrics.where((m) => m.kind == MetricKind.usedPercent).toList();
      expect(used, hasLength(2));
      expect(used[0].value, '25');
      expect(used[0].label, 'Codex principal usado');
      expect(used[0].resetsAt, DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true));
      expect(used[0].window, const Duration(minutes: 300));
      expect(used[1].value, '40');
      expect(used[1].label, 'Codex secundaria usado');

      final remaining = snapshot.metrics.where((m) => m.kind == MetricKind.remainingPercent).toList();
      expect(remaining[0].value, '75');
      expect(remaining[0].provenance, Provenance.derived);
      expect(remaining[1].value, '60');

      final tokens = snapshot.metrics.where((m) => m.kind == MetricKind.totalTokens).toList();
      expect(tokens.single.value, '123456');
      expect(tokens.single.label, 'Tokens acumulados');
      expect(snapshot.health, Health.healthy);
    });

    test('unauthorized fixture reports authentication error', () {
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      final snapshot = parseCodexResponses(configOf(ProviderKind.codex), Fixtures.read('codex_unauthorized.jsonl'), observed);
      expect(snapshot.health, Health.error);
      expect(snapshot.error!.code, 'unauthorized');
      expect(snapshot.error!.message, 'Codex no tiene una cuenta autenticada');
      expect(snapshot.metrics, isEmpty);
    });

    test('malformed JSONL fails closed', () {
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      expect(
        () => parseCodexResponses(configOf(ProviderKind.codex), '{"id":1, broken', observed),
        throwsA(
          isA<ProviderException>().having((e) => e.error.message, 'message', 'Codex app-server returned malformed JSONL'),
        ),
      );
    });

    test('missing account response throws', () {
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      expect(
        () => parseCodexResponses(configOf(ProviderKind.codex), '{"id":3,"result":{"rateLimits":{}}}', observed),
        throwsA(
          isA<ProviderException>()
              .having((e) => e.error.code, 'code', 'refresh-failed')
              .having((e) => e.error.message, 'message', 'Codex account response was not received'),
        ),
      );
    });
  });

  group('parseClaudeUsageText (claude_usage_screen.txt)', () {
    test('session and week percentages are parsed', () {
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      final snapshot = parseClaudeUsageText(configOf(ProviderKind.claudeSubscription), Fixtures.read('claude_usage_screen.txt'), observed);
      expect(snapshot, isNotNull);
      final used = snapshot!.metrics.where((m) => m.kind == MetricKind.usedPercent).toList();
      expect(used, hasLength(2));
      expect(used[0].value, '37');
      expect(used[0].label, 'Claude sesión usado');
      expect(used[0].provenance, Provenance.cliBridge);
      expect(used[1].value, '61');
      expect(used[1].label, 'Claude semana usado');
      final remaining = snapshot.metrics.where((m) => m.kind == MetricKind.remainingPercent).toList();
      expect(remaining[0].value, '63');
      expect(remaining[1].value, '39');
      expect(used[0].resetsAt, isNotNull);
    });

    test('percentage above 100 fails closed', () {
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      final output = 'Current session: 142% used · resets Aug 5, 7:10pm';
      expect(parseClaudeUsageText(configOf(ProviderKind.claudeSubscription), output, observed), isNull);
    });

    test('terminal cleanup strips ANSI sequences', () {
      const ansi = '\x1b[2J\x1b[1;31mCurrent session:\x1b[0m 12% used\x07';
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      final snapshot = parseClaudeUsageText(configOf(ProviderKind.claudeSubscription), ansi, observed);
      expect(snapshot, isNotNull);
      expect(snapshot!.metrics.where((m) => m.kind == MetricKind.usedPercent).single.value, '12');
    });

    test('no recognizable percentages returns null', () {
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      expect(
        parseClaudeUsageText(configOf(ProviderKind.claudeSubscription), 'no data here', observed),
        isNull,
      );
    });
  });

  group('parseOllamaStatus (ollama fixtures)', () {
    test('idle fixture yields zero loaded models', () {
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      final snapshot = parseOllamaStatus(configOf(ProviderKind.ollama), Fixtures.read('ollama_idle.json'), observed);
      expect(snapshot.metrics.single.kind, MetricKind.loadedModels);
      expect(snapshot.metrics.single.value, '0');
      expect(snapshot.health, Health.healthy);
    });

    test('loaded fixture reports memory and unload time', () {
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      final snapshot = parseOllamaStatus(configOf(ProviderKind.ollama), Fixtures.read('ollama_loaded.json'), observed);
      expect(snapshot.metrics, hasLength(2));
      final count = snapshot.metrics[0];
      expect(count.value, '1');
      final memory = snapshot.metrics[1];
      expect(memory.kind, MetricKind.resourceMemory);
      expect(memory.value, '1234567890');
      expect(memory.unit, MetricUnit.bytes);
      expect(memory.label, 'llama3.1:latest');
      expect(memory.resetsAt, DateTime.utc(2026, 9, 7, 12, 34, 56));
    });

    test('unloaded fixture has unsupported memory', () {
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      final snapshot = parseOllamaStatus(configOf(ProviderKind.ollama), Fixtures.read('ollama_unloaded.json'), observed);
      final memory = snapshot.metrics[1];
      expect(memory.value, '');
      expect(memory.availability, Availability.unsupported);
      expect(memory.resetsAt, isNull);
    });

    test('multi fixture counts all models', () {
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      final snapshot = parseOllamaStatus(configOf(ProviderKind.ollama), Fixtures.read('ollama_multi.json'), observed);
      expect(snapshot.metrics.first.value, '2');
    });

    test('unload offset fixture parses fractional seconds and offset', () {
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      final snapshot = parseOllamaStatus(configOf(ProviderKind.ollama), Fixtures.read('ollama_unload_offset.json'), observed);
      final memory = snapshot.metrics[1];
      expect(memory.value, '2147483648');
      // 2026-09-07T14:38:31.83753-07:00 == 21:38:31 UTC.
      expect(memory.resetsAt, DateTime.utc(2026, 9, 7, 21, 38, 31));
    });

    test('protected fixture omits expires_at', () {
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      final snapshot = parseOllamaStatus(configOf(ProviderKind.ollama), Fixtures.read('ollama_protected.json'), observed);
      expect(snapshot.metrics[1].resetsAt, isNull);
      expect(snapshot.metrics[1].availability, Availability.available);
    });

    test('invalid unload timestamp fails closed', () {
      final observed = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      expect(
        () => parseOllamaStatus(
          configOf(ProviderKind.ollama),
          '{"models":[{"name":"x","expires_at":"not-a-time"}]}',
          observed,
        ),
        throwsA(isA<ProviderException>()),
      );
    });
  });

  group('parseOllamaAccountLabel (account fixtures)', () {
    test('account fixture composes name and plan', () {
      expect(parseOllamaAccountLabel(Fixtures.read('ollama_account.json')), 'roviol (plan pro)');
    });

    test('anonymous fixture yields empty label', () {
      expect(parseOllamaAccountLabel(Fixtures.read('ollama_account_anonymous.json')), '');
    });
  });

  group('parseOllamaCloudUsage (cloud fixtures)', () {
    test('usage fixture converts fraction to percentages and counts', () {
      final metrics = parseOllamaCloudUsage(Fixtures.read('ollama_cloud_usage.json'));
      expect(metrics, hasLength(6));
      expect(metrics[0].kind, MetricKind.usedPercent);
      expect(metrics[0].value, '38.2');
      expect(metrics[0].label, 'Creditos mensuales usados');
      expect(metrics[1].kind, MetricKind.remainingPercent);
      expect(metrics[1].value, '61.8');
      expect(metrics[1].provenance, Provenance.derived);
      expect(metrics[2].label, 'glm-5.3-flash');
      expect(metrics[2].value, '2002');
      expect(metrics[5].value, '6');
      expect(metrics.where((m) => m.unit == MetricUnit.usd || m.unit == MetricUnit.cny), isEmpty);
    });

    test('idle cloud fixture yields zero percentages', () {
      final metrics = parseOllamaCloudUsage(Fixtures.read('ollama_cloud_idle.json'));
      expect(metrics[0].value, '0.0');
      expect(metrics[1].value, '100');
      expect(metrics, hasLength(2));
    });

    test('fraction outside 0..1 fails closed', () {
      const bad = '{"limits":{"monthly":{"usage":1.5}}}';
      expect(() => parseOllamaCloudUsage(bad), throwsA(isA<ProviderException>()));
    });
  });
}