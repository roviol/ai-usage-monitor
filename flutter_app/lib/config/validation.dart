/// Settings validation, per-kind defaults and overlay normalization, ported
/// from the C++ reference.
library;

import 'dart:io';

import '../domain/decimal.dart';
import '../domain/model.dart';
import 'settings.dart';

/// Clamps overlay opacity to 50..100.
int normalizeOverlayOpacity(int opacity) => opacity.clamp(50, 100);

/// Clamps overlay margin to 0..96.
int normalizeOverlayMargin(int margin) => margin.clamp(0, 96);

/// Returns the settings error message, or null when valid — mirroring the
/// reference's `ValidateSettings` rules and messages.
String? validateSettings(Settings settings) {
  if (settings.schemaVersion != 1) return 'unsupported settings schema';
  if (settings.refreshMinutes < 1 || settings.refreshMinutes > 60) {
    return 'refreshMinutes must be between 1 and 60';
  }
  if (settings.overlay.opacity < 50 || settings.overlay.opacity > 100) {
    return 'overlay opacity must be between 50 and 100';
  }
  if (settings.overlay.margin < 0 || settings.overlay.margin > 96) {
    return 'overlay margin must be between 0 and 96';
  }
  if (settings.overlay.monitor.length > 256) {
    return 'overlay monitor identifier is too long';
  }
  for (final provider in settings.providers) {
    if (provider.id.isEmpty || provider.name.isEmpty) {
      return 'provider id and name are required';
    }
    if (provider.kind == ProviderKind.ollama && provider.baseUrl.isEmpty) {
      return 'provider base URL is required for Ollama';
    }
    final budget = provider.budget;
    if (budget != null && (!isDecimal(budget) || budget.startsWith('-'))) {
      return 'provider budget must be a non-negative decimal';
    }
    if (provider.encryptedCloudKey.isNotEmpty && provider.kind != ProviderKind.ollama) {
      return 'cloud credentials are only used by the Ollama provider';
    }
    for (final route in [provider.usagePath, provider.balancePath]) {
      if (route.length > 2048 || route.contains('://') || (route.isNotEmpty && !route.startsWith('/'))) {
        return "provider routes must be bounded same-origin paths beginning with '/'";
      }
    }
    if (provider.jsonPointers.length > 16) {
      return 'a provider may define at most 16 JSON Pointer mappings';
    }
    for (final pointer in provider.jsonPointers.values) {
      if (pointer.isEmpty || pointer.length > 2048 || !pointer.startsWith('/')) {
        return 'invalid JSON Pointer mapping';
      }
      if (!_isValidJsonPointer(pointer)) {
        return 'invalid JSON Pointer mapping';
      }
    }
  }
  return null;
}

/// Validates a JSON Pointer syntactically like `nlohmann::json::json_pointer`
/// construction does (non-empty, leading `/`, no invalid escapes or trailing
/// tilde).
bool _isValidJsonPointer(String pointer) {
  if (!pointer.startsWith('/')) return false;
  var index = 0;
  while (index < pointer.length) {
    if (pointer[index] != '/') return false;
    index++;
    var token = '';
    while (index < pointer.length && pointer[index] != '/') {
      token += pointer[index];
      index++;
    }
    if (token.contains('~') && !_validPointerEscape(token)) {
      return false;
    }
  }
  return true;
}

bool _validPointerEscape(String token) {
  for (var i = 0; i < token.length; i++) {
    if (token[i] == '~') {
      if (i + 1 >= token.length || (token[i + 1] != '0' && token[i + 1] != '1')) {
        return false;
      }
      i++;
    }
  }
  return true;
}

/// Defaults applied when creating a provider of [kind], matching
/// `DefaultsForKind`.
ProviderKindDefaults defaultsForKind(ProviderKind kind) {
  switch (kind) {
    case ProviderKind.deepSeek:
      return ProviderKindDefaults(
        baseUrl: 'https://api.deepseek.com',
        balancePath: '/user/balance',
      );
    case ProviderKind.ollama:
      return ProviderKindDefaults(
        baseUrl: 'http://localhost:11434',
        allowLoopbackHttp: true,
      );
    case ProviderKind.codex:
    case ProviderKind.claudeSubscription:
    case ProviderKind.openAiCompatible:
      return ProviderKindDefaults();
  }
}

/// Rewrites an absolute configured executable to the portable command name
/// when it refers to the same file as the discovered executable.
String makeExecutableReferencePortable(
  String command,
  String configured,
  String? discovered,
) {
  if (configured.isEmpty || discovered == null || discovered.isEmpty) return configured;
  if (_sameFile(configured, discovered)) return command;
  if (_normalize(configured) == _normalize(discovered)) return command;
  return configured;
}

bool _sameFile(String a, String b) {
  try {
    if (!File(a).existsSync() || !File(b).existsSync()) return false;
    final statA = File(a).statSync();
    final statB = File(b).statSync();
    return statA.changed == statB.changed &&
        statA.modified == statB.modified &&
        statA.size == statB.size;
  } catch (_) {
    return false;
  }
}

String _normalize(String path) {
  try {
    return File(path).absolute.resolveSymbolicLinksSync().replaceAll('\\', '/');
  } catch (_) {
    return path;
  }
}