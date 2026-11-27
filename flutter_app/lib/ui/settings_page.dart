/// Settings interface ported from `src/ui/settings_dialog.cpp`: provider list
/// with add/remove/selection, per-kind field visibility, credential
/// persistence, connection testing with redaction, save validation with the
/// reference Spanish messages, and compact layout.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../config/validation.dart';
import '../domain/model.dart';
import '../platform/interfaces.dart';
import '../platform/io_impl.dart';
import '../platform/url_policy.dart';
import '../providers/providers.dart';
import 'theme.dart';

/// Provider kind labels shown in the settings choices, mirroring
/// `KindLabels`.
const Map<ProviderKind, String> kindLabels = {
  ProviderKind.codex: 'Codex',
  ProviderKind.claudeSubscription: 'Claude /usage local',
  ProviderKind.deepSeek: 'DeepSeek',
  ProviderKind.ollama: 'Ollama',
  ProviderKind.openAiCompatible: 'OpenAI-compatible',
};

const List<ProviderKind> _kindOrder = [
  ProviderKind.codex,
  ProviderKind.claudeSubscription,
  ProviderKind.deepSeek,
  ProviderKind.ollama,
  ProviderKind.openAiCompatible,
];

/// Generates a provider identifier like the reference's `NewId`.
String newProviderId(ProviderKind kind, DateTime now) =>
    '${kind.wire}-${now.millisecondsSinceEpoch}';

/// Field visibility per provider kind, mirroring `UpdateFieldVisibility`.
class FieldVisibility {
  const FieldVisibility({
    required this.local,
    required this.http,
    required this.generic,
    required this.ollama,
    required this.deepSeek,
  });

  factory FieldVisibility.forKind(ProviderKind kind) {
    final local = kind == ProviderKind.codex || kind == ProviderKind.claudeSubscription;
    final http = kind == ProviderKind.deepSeek ||
        kind == ProviderKind.openAiCompatible ||
        kind == ProviderKind.ollama;
    final generic = kind == ProviderKind.openAiCompatible;
    final ollama = kind == ProviderKind.ollama;
    final deepSeek = kind == ProviderKind.deepSeek;
    return FieldVisibility(
      local: local,
      http: http,
      generic: generic,
      ollama: ollama,
      deepSeek: deepSeek,
    );
  }

  final bool local;
  final bool http;
  final bool generic;
  final bool ollama;
  final bool deepSeek;

  bool get executable => local;
  bool get baseUrl => http;
  bool get apiKey => http;
  bool get cloudKey => ollama;
  bool get usagePath => generic;
  bool get balancePath => deepSeek || generic;
  bool get budget => deepSeek;
  bool get mappings => generic;
  bool get loopback => http;
  bool get persistKey => http;
}

/// Parses the mappings text area (`key=/pointer` lines) like the reference.
Map<String, String> parseMappingsText(String text) {
  final pointers = <String, String>{};
  for (final line in text.split('\n')) {
    final equals = line.indexOf('=');
    if (equals > 0 && equals + 1 < line.length) {
      pointers[line.substring(0, equals)] = line.substring(equals + 1);
    }
  }
  return pointers;
}

/// Serializes mappings for the text area.
String mappingsToText(Map<String, String> pointers) => [
      for (final entry in pointers.entries) '${entry.key}=${entry.value}',
    ].join('\n');

/// Result of applying the settings editor state.
class SettingsSaveResult {
  const SettingsSaveResult({required this.success, this.message = '', this.saved});

  final bool success;
  final String message;
  final Settings? saved;
}

/// Controller-level settings editing logic, extracted from the widget so the
/// save/cancel/add/remove semantics are unit-testable.
class SettingsEditor {
  SettingsEditor({required Settings initial, DateTime Function()? now})
      : working = initial.copy(),
        _now = now ?? DateTime.now;

  final DateTime Function() _now;
  Settings working;

  ProviderConfig? addProvider(ProviderKind kind) {
    final defaults = defaultsForKind(kind);
    final provider = ProviderConfig(
      id: newProviderId(kind, _now()),
      name: kindLabels[kind] ?? kind.wire,
      kind: kind,
      baseUrl: defaults.baseUrl,
      balancePath: defaults.balancePath,
      allowLoopbackHttp: defaults.allowLoopbackHttp,
    );
    if (kind == ProviderKind.codex && discoverExecutable('codex') != null) {
      provider.executable = 'codex';
    }
    if (kind == ProviderKind.claudeSubscription && discoverExecutable('claude') != null) {
      provider.executable = 'claude';
    }
    working.providers.add(provider);
    return provider;
  }

  ProviderConfig? removeAt(int index) {
    if (index < 0 || index >= working.providers.length) return null;
    final removed = working.providers.removeAt(index);
    return removed;
  }

  /// Clears stored credentials for the provider at [index].
  void forgetKeys(int index) {
    if (index < 0 || index >= working.providers.length) return;
    final provider = working.providers[index];
    provider.encryptedApiKey = '';
    provider.encryptedCloudKey = '';
  }

  /// Applies the editor's fields onto the provider at [index], with the
  /// reference's credential persistence rules and cloud-key clearing.
  Future<void> applyProviderFields(
    int index, {
    required String name,
    required ProviderKind kind,
    required bool enabled,
    required String executable,
    required String baseUrl,
    required String apiKey,
    required String cloudKey,
    required bool persistKey,
    required bool persistentAvailable,
    required String usagePath,
    required String balancePath,
    required String budget,
    required Map<String, String> jsonPointers,
    required bool allowLoopbackHttp,
    required SecretStore secrets,
  }) async {
    if (index < 0 || index >= working.providers.length) {
      return;
    }
    final provider = working.providers[index];
    provider.name = name;
    provider.kind = kind;
    provider.enabled = enabled;
    provider.executable = executable;
    provider.baseUrl = baseUrl;
    if (cloudKey.isNotEmpty) {
      provider.encryptedCloudKey = persistKey && persistentAvailable
          ? await secrets.protect(cloudKey)
          : secrets.protectSession(cloudKey);
    }
    // The cloud credential only ever reaches ollama.com, so it must not
    // survive a switch to a provider type that talks to a different host.
    if (provider.kind != ProviderKind.ollama) {
      provider.encryptedCloudKey = '';
    }
    if (apiKey.isNotEmpty) {
      provider.encryptedApiKey = persistKey && persistentAvailable
          ? await secrets.protect(apiKey)
          : secrets.protectSession(apiKey);
    }
    provider.usagePath = usagePath;
    provider.balancePath = balancePath;
    provider.budget = budget.isEmpty ? null : budget;
    provider.jsonPointers
      ..clear()
      ..addAll(jsonPointers);
    provider.allowLoopbackHttp = allowLoopbackHttp;
  }

  /// Validates the working configuration with the reference's per-provider
  /// Spanish messages plus `ValidateSettings`.
  String? validate() {
    for (final provider in working.providers) {
      if (provider.enabled &&
          (provider.kind == ProviderKind.codex || provider.kind == ProviderKind.claudeSubscription) &&
          provider.executable.isEmpty) {
        return 'Seleccione un ejecutable compatible para ${provider.name}.';
      }
      if ((provider.kind == ProviderKind.deepSeek ||
              provider.kind == ProviderKind.openAiCompatible ||
              provider.kind == ProviderKind.ollama) &&
          provider.baseUrl.isEmpty) {
        return 'La URL base es obligatoria para ${provider.name}.';
      }
      if (provider.baseUrl.isNotEmpty && !isSafeEndpointUrl(provider.baseUrl, provider.allowLoopbackHttp)) {
        return 'La URL de ${provider.name} debe usar HTTPS o loopback explícito.';
      }
      for (final pointer in provider.jsonPointers.values) {
        if (pointer.isEmpty || !pointer.startsWith('/')) {
          return "Los JSON Pointer deben comenzar con '/'.";
        }
      }
    }
    return validateSettings(working);
  }

  /// Carries default-shaped values to the new kind's defaults on a kind
  /// switch, mirroring `OnKindChanged`.
  void switchKind(ProviderConfig provider, ProviderKind previousKind, ProviderKind nextKind) {
    final previous = defaultsForKind(previousKind);
    final next = defaultsForKind(nextKind);
    if (provider.baseUrl.isEmpty || provider.baseUrl == previous.baseUrl) {
      provider.baseUrl = next.baseUrl;
    }
    if (provider.balancePath.isEmpty || provider.balancePath == previous.balancePath) {
      provider.balancePath = next.balancePath;
    }
    if (provider.allowLoopbackHttp == previous.allowLoopbackHttp) {
      provider.allowLoopbackHttp = next.allowLoopbackHttp;
    }
    if (provider.name == kindLabels[previousKind]) {
      provider.name = kindLabels[nextKind] ?? provider.name;
    }
    provider.kind = nextKind;
  }
}

/// Connection-test behavior shared by the settings window: rejects unsafe
/// URLs, redacts secrets, and appends the capability detail.
class ConnectionTester {
  ConnectionTester({required this.http, required this.process, required this.secrets});

  final HttpTransport http;
  final ProcessRunner process;
  final SecretStore secrets;

  Future<ConnectionTestResult> test(ProviderConfig config) async {
    if (config.baseUrl.isNotEmpty && !isSafeEndpointUrl(config.baseUrl, config.allowLoopbackHttp)) {
      return const ConnectionTestResult(
        success: false,
        capabilities: ProviderCapabilities(),
        message: 'URL rechazada: use HTTPS o HTTP loopback habilitado.',
      );
    }
    ConnectionTestResult result;
    try {
      final provider = createProvider(config, http, process, secrets, SystemClock());
      result = await provider.testConnection();
    } catch (error) {
      result = ConnectionTestResult(
        success: false,
        capabilities: const ProviderCapabilities(),
        message: error.toString(),
      );
    }
    final sensitive = <String>[];
    if (config.encryptedApiKey.isNotEmpty) {
      try {
        sensitive.add(await secrets.unprotect(config.encryptedApiKey));
      } catch (_) {}
    }
    final message = redactSecrets(result.message, sensitive);
    return ConnectionTestResult(
      success: result.success,
      capabilities: result.capabilities,
      message: result.capabilities.detail.isEmpty
          ? message
          : '$message | ${result.capabilities.detail}',
    );
  }
}

/// The settings window: global preferences, overlay preferences, provider
/// list and editor with per-kind visibility.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.initial,
    required this.secrets,
    required this.tester,
    required this.onSave,
    required this.onCancel,
    this.dataFolderAction,
  });

  final Settings initial;
  final SecretStore secrets;
  final ConnectionTester tester;
  final ValueChanged<Settings> onSave;
  final VoidCallback onCancel;
  final VoidCallback? dataFolderAction;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final SettingsEditor _editor = SettingsEditor(initial: widget.initial);
  late int _selected = widget.initial.providers.isEmpty ? -1 : 0;
  late final _refreshMinutes = TextEditingController(text: widget.initial.refreshMinutes.toString());
  final _name = TextEditingController();
  final _executable = TextEditingController();
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _cloudKey = TextEditingController();
  final _usagePath = TextEditingController();
  final _balancePath = TextEditingController();
  final _budget = TextEditingController();
  final _mappings = TextEditingController();
  bool _enabled = false;
  bool _persistKey = true;
  bool _loopback = false;
  ProviderKind _editorKind = ProviderKind.openAiCompatible;
  String? _validationError;
  String? _testResult;
  bool _testSuccess = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    if (_selected >= 0) _loadSelected();
  }

  void _loadSelected() {
    final providers = _editor.working.providers;
    if (_selected < 0 || _selected >= providers.length) return;
    final provider = providers[_selected];
    _name.text = provider.name;
    _editorKind = provider.kind;
    _enabled = provider.enabled;
    _executable.text = provider.executable;
    _baseUrl.text = provider.baseUrl;
    _apiKey.clear();
    _cloudKey.clear();
    _usagePath.text = provider.usagePath;
    _balancePath.text = provider.balancePath;
    _budget.text = provider.budget ?? '';
    _mappings.text = mappingsToText(provider.jsonPointers);
    _loopback = provider.allowLoopbackHttp;
    _validationError = null;
  }

  void _saveSelected() {
    _editor.applyProviderFields(
      _selected,
      name: _name.text,
      kind: _editorKind,
      enabled: _enabled,
      executable: _executable.text,
      baseUrl: _baseUrl.text,
      apiKey: _apiKey.text,
      cloudKey: _cloudKey.text,
      persistKey: _persistKey,
      persistentAvailable: widget.secrets.persistentAvailable(),
      usagePath: _usagePath.text,
      balancePath: _balancePath.text,
      budget: _budget.text,
      jsonPointers: parseMappingsText(_mappings.text),
      allowLoopbackHttp: _loopback,
      secrets: widget.secrets,
    );
  }

  void _refreshEditor() {
    setState(() {});
  }

  Future<void> _save() async {
    setState(() {
      _validationError = null;
    });
    try {
      _saveSelected();
      _editor.working
        ..refreshMinutes = int.tryParse(_refreshMinutes.text) ?? _editor.working.refreshMinutes
        ..alwaysOnTop = _editor.working.alwaysOnTop;
      final error = _editor.validate();
      if (error != null) {
        setState(() {
          _validationError = '× $error';
        });
        await _showInvalidDialog(error);
        return;
      }
      widget.onSave(_editor.working);
    } catch (error) {
      setState(() {
        _validationError = '× $error';
      });
      await _showInvalidDialog(error.toString());
    }
  }

  Future<void> _showInvalidDialog(String message) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configuración inválida'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  Future<void> _testConnection() async {
    _saveSelected();
    if (_selected < 0) return;
    final config = _editor.working.providers[_selected];
    setState(() {
      _testing = true;
      _testResult = '↻ Probando…';
      _testSuccess = false;
    });
    final result = await widget.tester.test(config);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testSuccess = result.success;
      _testResult = '${result.success ? '✓ ' : '× Error: '}${result.message}';
    });
  }

  void _remove() {
    if (_selected < 0) return;
    _editor.removeAt(_selected);
    _selected = _editor.working.providers.isEmpty
        ? -1
        : _selected.clamp(0, _editor.working.providers.length - 1);
    if (_selected >= 0) _loadSelected();
    _refreshEditor();
  }

  void _forgetKeys() {
    _editor.forgetKeys(_selected);
    _apiKey.clear();
    _cloudKey.clear();
    setState(() {
      _testResult = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = useCompactLayout(width.round(), 720);
    final editor = _selected >= 0 && _selected < _editor.working.providers.length
        ? _editor.working.providers[_selected]
        : null;
    final visibility = editor == null ? null : FieldVisibility.forKind(_editorKind);
    final body = compact
        ? Column(
            children: [_navigationPanel(), Expanded(child: _editorPanel(editor, visibility))],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 280, child: _navigationPanel()),
              Expanded(child: _editorPanel(editor, visibility)),
            ],
          );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración · AI Usage Monitor'),
        actions: [
          TextButton(onPressed: widget.onCancel, child: const Text('Cancelar')),
          TextButton(onPressed: _save, child: const Text('Guardar cambios')),
        ],
      ),
      body: body,
    );
  }

  Widget _navigationPanel() {
    final providers = _editor.working.providers;
    return Card(
      margin: const EdgeInsets.all(Spacing.md),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Proveedores', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            for (var i = 0; i < providers.length; i++)
              ListTile(
                dense: true,
                selected: i == _selected,
                title: Text(providers[i].name),
                subtitle: Text(kindLabels[providers[i].kind] ?? providers[i].kind.wire),
                onTap: () {
                  _saveSelected();
                  setState(() {
                    _selected = i;
                    _loadSelected();
                  });
                },
              ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ProviderKind>(
                    initialValue: ProviderKind.openAiCompatible,
                    decoration: const InputDecoration(labelText: 'Tipo de proveedor nuevo'),
                    items: [
                      for (final kind in _kindOrder)
                        DropdownMenuItem(value: kind, child: Text(kindLabels[kind] ?? kind.wire)),
                    ],
                    onChanged: (kind) {
                      if (kind == null) return;
                      _saveSelected();
                      _editor.addProvider(kind);
                      setState(() {
                        _selected = _editor.working.providers.length - 1;
                        _loadSelected();
                      });
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Eliminar proveedor',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _remove,
                ),
              ],
            ),
            const Divider(),
            Text('Preferencias generales', style: Theme.of(context).textTheme.titleSmall),
            TextFormField(
              controller: _refreshMinutes,
              decoration: const InputDecoration(labelText: 'Refresco (minutos)'),
              keyboardType: TextInputType.number,
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: widget.dataFolderAction,
                    child: const Text('Abrir carpeta de datos'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _editorPanel(ProviderConfig? provider, FieldVisibility? visibility) {
    if (provider == null || visibility == null) {
      return const Center(child: Text('Seleccione un proveedor'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Identidad y cliente local', style: Theme.of(context).textTheme.titleSmall),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          DropdownButtonFormField<ProviderKind>(
            initialValue: _editorKind,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: [
              for (final kind in _kindOrder)
                DropdownMenuItem(value: kind, child: Text(kindLabels[kind] ?? kind.wire)),
            ],
            onChanged: (kind) {
              if (kind == null || kind == _editorKind) return;
              setState(() {
                _editor.switchKind(provider, _editorKind, kind);
                _editorKind = kind;
                _loadSelected();
              });
            },
          ),
          if (visibility.executable)
            TextFormField(
              controller: _executable,
              decoration: const InputDecoration(labelText: 'Ejecutable del cliente'),
            ),
          const SizedBox(height: Spacing.md),
          if (visibility.http) ...[
            Text('Conexión', style: Theme.of(context).textTheme.titleSmall),
            TextFormField(
              controller: _baseUrl,
              decoration: const InputDecoration(labelText: 'URL base'),
            ),
            TextFormField(
              controller: _apiKey,
              decoration: InputDecoration(
                labelText: 'API key del servidor',
                hintText: provider.encryptedApiKey.isEmpty ? null : '•••• guardada',
              ),
              obscureText: true,
            ),
            if (visibility.cloudKey)
              TextFormField(
                controller: _cloudKey,
                decoration: const InputDecoration(labelText: 'API key de ollama.com'),
                obscureText: true,
              ),
            CheckboxListTile(
              title: const Text('Proveedor habilitado'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value ?? false),
            ),
            CheckboxListTile(
              title: const Text('Guardar clave en almacenamiento seguro'),
              value: _persistKey,
              onChanged: (value) => setState(() => _persistKey = value ?? true),
            ),
            if (!widget.secrets.persistentAvailable())
              const Text('Almacenamiento persistente no disponible; las claves son solo de esta sesión.'),
            CheckboxListTile(
              title: const Text('Permitir HTTP sólo para loopback'),
              value: _loopback,
              onChanged: (value) => setState(() => _loopback = value ?? false),
            ),
            Row(
              children: [
                FilledButton.tonal(
                  onPressed: _testing ? null : _testConnection,
                  child: Text(_testing ? 'Probando…' : 'Probar conexión'),
                ),
                const SizedBox(width: Spacing.sm),
                TextButton(onPressed: _forgetKeys, child: const Text('Olvidar claves guardadas')),
              ],
            ),
            if (_testResult != null)
              Text(
                _testResult!,
                style: TextStyle(
                  color: _testSuccess ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
                ),
              ),
          ],
          if (visibility.usagePath || visibility.balancePath || visibility.mappings) ...[
            const SizedBox(height: Spacing.md),
            Text('Uso y mappings', style: Theme.of(context).textTheme.titleSmall),
            if (visibility.usagePath)
              TextFormField(
                controller: _usagePath,
                decoration: const InputDecoration(labelText: 'Ruta de uso'),
              ),
            if (visibility.balancePath)
              TextFormField(
                controller: _balancePath,
                decoration: const InputDecoration(labelText: 'Ruta de saldo'),
              ),
            if (visibility.deepSeek)
              TextFormField(
                controller: _budget,
                decoration: const InputDecoration(labelText: 'Presupuesto'),
              ),
            if (visibility.mappings)
              TextFormField(
                controller: _mappings,
                decoration: const InputDecoration(
                  labelText: 'Mappings JSON Pointer',
                  hintText: 'used_percent=/usage/percent',
                ),
                maxLines: 4,
              ),
          ],
          if (_validationError != null)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.md),
              child: Text(
                _validationError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
