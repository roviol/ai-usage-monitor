import 'package:flutter_test/flutter_test.dart';
import 'package:ai_usage_monitor/config/config.dart';
import 'package:ai_usage_monitor/domain/domain.dart';
import 'package:ai_usage_monitor/platform/platform.dart';
import 'package:ai_usage_monitor/ui/settings_page.dart';

void main() {
  group('SettingsEditor add/remove defaults', () {
    test('add creates a kind-defaulted disabled provider with generated id', () {
      final editor = SettingsEditor(initial: Settings());
      final added = editor.addProvider(ProviderKind.ollama);
      expect(added, isNotNull);
      expect(added!.id, startsWith('ollama-'));
      expect(added.name, 'Ollama');
      expect(added.baseUrl, 'http://localhost:11434');
      expect(added.allowLoopbackHttp, isTrue);
      expect(added.enabled, isFalse);
      expect(added.balancePath, '');
    });

    test('deepseek defaults are applied on add', () {
      final editor = SettingsEditor(initial: Settings());
      final added = editor.addProvider(ProviderKind.deepSeek);
      expect(added!.baseUrl, 'https://api.deepseek.com');
      expect(added.balancePath, '/user/balance');
      expect(added.enabled, isFalse);
    });

    test('remove drops the selected provider', () {
      final editor = SettingsEditor(
        initial: Settings(
          providers: [
            ProviderConfig(id: 'a', name: 'A'),
            ProviderConfig(id: 'b', name: 'B'),
          ],
        ),
      );
      editor.removeAt(0);
      expect(editor.working.providers.map((p) => p.id), ['b']);
      expect(editor.removeAt(9), isNull);
      expect(editor.removeAt(-1), isNull);
    });
  });

  group('field visibility per kind', () {
    test('local providers show only executables', () {
      for (final kind in [ProviderKind.codex, ProviderKind.claudeSubscription]) {
        final visibility = FieldVisibility.forKind(kind);
        expect(visibility.executable, isTrue, reason: kind.wire);
        expect(visibility.baseUrl, isFalse);
        expect(visibility.apiKey, isFalse);
        expect(visibility.cloudKey, isFalse);
        expect(visibility.mappings, isFalse);
      }
    });

    test('http providers show URL, credential and routes', () {
      final visibility = FieldVisibility.forKind(ProviderKind.deepSeek);
      expect(visibility.baseUrl, isTrue);
      expect(visibility.apiKey, isTrue);
      expect(visibility.balancePath, isTrue);
      expect(visibility.budget, isTrue);
      expect(visibility.cloudKey, isFalse);
      expect(visibility.mappings, isFalse);
    });

    test('ollama is the only kind with a cloud key', () {
      expect(FieldVisibility.forKind(ProviderKind.ollama).cloudKey, isTrue);
      for (final kind in [ProviderKind.codex, ProviderKind.deepSeek, ProviderKind.openAiCompatible]) {
        expect(FieldVisibility.forKind(kind).cloudKey, isFalse, reason: kind.wire);
      }
    });

    test('generic provider shows routes and mappings', () {
      final visibility = FieldVisibility.forKind(ProviderKind.openAiCompatible);
      expect(visibility.generic, isTrue);
      expect(visibility.usagePath, isTrue);
      expect(visibility.mappings, isTrue);
      expect(visibility.budget, isFalse);
    });
  });

  group('credential persistence', () {
    test('persistent store protects when enabled', () async {
      final secrets = FakeSecretStore(persistent: true);
      final editor = SettingsEditor(
        initial: Settings(providers: [ProviderConfig(id: 'a', name: 'A', kind: ProviderKind.ollama)]),
      );
      await editor.applyProviderFields(
        0,
        name: 'A',
        kind: ProviderKind.ollama,
        enabled: true,
        executable: '',
        baseUrl: 'http://localhost:11434',
        apiKey: 'sk-plain',
        cloudKey: '',
        persistKey: true,
        persistentAvailable: secrets.persistentAvailable(),
        usagePath: '',
        balancePath: '',
        budget: '',
        jsonPointers: {},
        allowLoopbackHttp: true,
        secrets: secrets,
      );
      expect(editor.working.providers.single.encryptedApiKey, startsWith('secret-service:'));
    });

    test('session fallback emits session tokens', () async {
      final secrets = FakeSecretStore();
      final editor = SettingsEditor(
        initial: Settings(providers: [ProviderConfig(id: 'a', name: 'A', kind: ProviderKind.ollama)]),
      );
      await editor.applyProviderFields(
        0,
        name: 'A',
        kind: ProviderKind.ollama,
        enabled: true,
        executable: '',
        baseUrl: 'http://localhost:11434',
        apiKey: 'sk-plain',
        cloudKey: '',
        persistKey: true,
        persistentAvailable: secrets.persistentAvailable(),
        usagePath: '',
        balancePath: '',
        budget: '',
        jsonPointers: {},
        allowLoopbackHttp: true,
        secrets: secrets,
      );
      expect(editor.working.providers.single.encryptedApiKey, startsWith('session:'));
    });

    test('cloud credentials clear on kind change away from Ollama', () async {
      final secrets = FakeSecretStore(persistent: true);
      final provider = ProviderConfig(
        id: 'a',
        name: 'A',
        kind: ProviderKind.ollama,
        baseUrl: 'http://localhost:11434',
        encryptedCloudKey: 'secret-service:abc',
      );
      final editor = SettingsEditor(initial: Settings(providers: [provider]));
      await editor.applyProviderFields(
        0,
        name: 'A',
        kind: ProviderKind.deepSeek,
        enabled: false,
        executable: '',
        baseUrl: 'https://api.deepseek.com',
        apiKey: '',
        cloudKey: '',
        persistKey: true,
        persistentAvailable: true,
        usagePath: '',
        balancePath: '/user/balance',
        budget: '',
        jsonPointers: {},
        allowLoopbackHttp: false,
        secrets: secrets,
      );
      expect(editor.working.providers.single.kind, ProviderKind.deepSeek);
      expect(editor.working.providers.single.encryptedCloudKey, '');
    });

    test('forget keys clears stored credentials', () {
      final editor = SettingsEditor(
        initial: Settings(
          providers: [
            ProviderConfig(
              id: 'a',
              name: 'A',
              encryptedApiKey: 'secret-service:ab',
              encryptedCloudKey: 'session:cd',
            ),
          ],
        ),
      );
      editor.forgetKeys(0);
      expect(editor.working.providers.single.encryptedApiKey, '');
      expect(editor.working.providers.single.encryptedCloudKey, '');
    });
  });

  group('save validation', () {
    test('rejects missing executable with the reference message', () {
      final editor = SettingsEditor(
        initial: Settings(
          providers: [
            ProviderConfig(id: 'a', name: 'Codex', kind: ProviderKind.codex, enabled: true, executable: ''),
          ],
        ),
      );
      expect(editor.validate(), 'Seleccione un ejecutable compatible para Codex.');
    });

    test('rejects missing base URL with the reference message', () {
      final editor = SettingsEditor(
        initial: Settings(
          providers: [ProviderConfig(id: 'a', name: 'Ollama', kind: ProviderKind.ollama, baseUrl: '')],
        ),
      );
      expect(editor.validate(), 'La URL base es obligatoria para Ollama.');
    });

    test('rejects unsafe URL with the reference message', () {
      final editor = SettingsEditor(
        initial: Settings(
          providers: [
            ProviderConfig(id: 'a', name: 'DeepSeek', kind: ProviderKind.deepSeek, baseUrl: 'http://api.example.com'),
          ],
        ),
      );
      expect(editor.validate(), 'La URL de DeepSeek debe usar HTTPS o loopback explícito.');
    });

    test('rejects pointers not starting with slash', () {
      final provider = ProviderConfig(id: 'a', name: 'G', kind: ProviderKind.openAiCompatible, baseUrl: 'https://x');
      provider.jsonPointers['used_percent'] = 'usage';
      final editor = SettingsEditor(initial: Settings(providers: [provider]));
      expect(editor.validate(), "Los JSON Pointer deben comenzar con '/'.");
    });

    test('delegates to ValidateSettings for schema rules', () {
      final editor = SettingsEditor(initial: Settings(refreshMinutes: 0));
      expect(editor.validate(), 'refreshMinutes must be between 1 and 60');
    });

    test('accepts a valid configuration', () {
      final editor = SettingsEditor(
        initial: Settings(
          providers: [
            ProviderConfig(
              id: 'a',
              name: 'DeepSeek',
              kind: ProviderKind.deepSeek,
              baseUrl: 'https://api.deepseek.com',
              balancePath: '/user/balance',
              encryptedApiKey: 'dpapi:AA',
            ),
          ],
        ),
      );
      expect(editor.validate(), isNull);
    });
  });

  group('kind switch carry-over', () {
    test('default-shaped values retype to the new kind defaults', () {
      final editor = SettingsEditor(initial: Settings());
      final provider = ProviderConfig(
        id: 'a',
        name: 'DeepSeek',
        kind: ProviderKind.deepSeek,
        baseUrl: 'https://api.deepseek.com',
        balancePath: '/user/balance',
      );
      editor.switchKind(provider, ProviderKind.deepSeek, ProviderKind.ollama);
      expect(provider.baseUrl, 'http://localhost:11434');
      expect(provider.balancePath, '');
      expect(provider.allowLoopbackHttp, isTrue);
      expect(provider.name, 'Ollama');
      expect(provider.kind, ProviderKind.ollama);
    });

    test('user-typed values are preserved', () {
      final editor = SettingsEditor(initial: Settings());
      final provider = ProviderConfig(
        id: 'a',
        name: 'Mi servidor',
        kind: ProviderKind.deepSeek,
        baseUrl: 'https://custom.example.com',
        balancePath: '/custom/balance',
      );
      editor.switchKind(provider, ProviderKind.deepSeek, ProviderKind.openAiCompatible);
      expect(provider.baseUrl, 'https://custom.example.com');
      expect(provider.balancePath, '/custom/balance');
      expect(provider.name, 'Mi servidor');
    });
  });

  group('mappings parsing', () {
    test('key=pointer lines are parsed', () {
      expect(parseMappingsText('used_percent=/usage/percent\ntotal_tokens=/usage/tokens\nbadline'), {
        'used_percent': '/usage/percent',
        'total_tokens': '/usage/tokens',
      });
    });

    test('mappings serialize round trip', () {
      final text = mappingsToText({'a': '/x', 'b': '/y'});
      expect(parseMappingsText(text), {'a': '/x', 'b': '/y'});
    });
  });

  group('connection testing', () {
    test('rejects unsafe URL before sending', () async {
      final tester = ConnectionTester(
        http: FakeHttpTransport(),
        process: FakeProcessRunner(),
        secrets: FakeSecretStore(),
      );
      final result = await tester.test(
        ProviderConfig(id: 'a', name: 'A', kind: ProviderKind.deepSeek, baseUrl: 'http://remote.example.com'),
      );
      expect(result.success, isFalse);
      expect(result.message, 'URL rechazada: use HTTPS o HTTP loopback habilitado.');
    });

    test('redacts credential material and appends capability detail', () async {
      final secrets = FakeSecretStore();
      final token = secrets.protectSession('sk-secret');
      final http = FakeHttpTransport()..enqueueResponse(200, '{}');
      final tester = ConnectionTester(http: http, process: FakeProcessRunner(), secrets: secrets);
      final config = ProviderConfig(
        id: 'a',
        name: 'A',
        kind: ProviderKind.openAiCompatible,
        baseUrl: 'https://example.com',
        encryptedApiKey: token,
      );
      final result = await tester.test(config);
      expect(result.message, isNot(contains('sk-secret')));
      expect(result.message, contains('Mappings explícitos'));
    });

    test('failed test reports the error message', () async {
      final http = FakeHttpTransport()..enqueueResponse(401, 'nope');
      final tester = ConnectionTester(http: http, process: FakeProcessRunner(), secrets: FakeSecretStore());
      final result = await tester.test(
        ProviderConfig(id: 'a', name: 'A', kind: ProviderKind.openAiCompatible, baseUrl: 'https://example.com'),
      );
      expect(result.success, isFalse);
      expect(result.message, contains('authentication rejected'));
    });
  });

  group('newProviderId', () {
    test('includes the kind wire and timestamp', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true);
      expect(newProviderId(ProviderKind.codex, now), 'codex-1785942000000');
    });
  });
}