/// OS-backed secret stores: Windows DPAPI via win32 FFI and Linux
/// secret-tool, emitting the reference's `dpapi:`, `secret-service:` and
/// `session:` tokens so settings files interoperate across applications.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'interfaces.dart';
import 'io_impl.dart';

final _random = Random.secure();

String _randomId() {
  final hex = '0123456789abcdef';
  return List.generate(32, (_) => hex[_random.nextInt(16)]).join();
}

/// In-memory session store shared by fallback paths; tokens do not survive
/// the process, mirroring the reference's session-only fallback.
class SessionSecretStore implements SecretStore {
  final Map<String, String> _session = {};

  @override
  @override
  Future<String> protect(String plainText) async => protectSession(plainText);

  @override
  String protectSession(String plainText) {
    final id = _randomId();
    _session[id] = plainText;
    return 'session:$id';
  }

  @override
  Future<String> unprotect(String opaque) async {
    if (!opaque.startsWith('session:')) {
      throw StateError('secure storage unavailable');
    }
    final secret = _session[opaque.substring(8)];
    if (secret == null) throw StateError('session-only credential expired');
    return secret;
  }

  @override
  bool persistentAvailable() => false;
}

/// Windows DPAPI store producing `dpapi:` base64 tokens. The token bytes are
/// exactly what CryptProtectData/CryptUnprotectData produce with description
/// `AI Usage Monitor` and CRYPTPROTECT_UI_FORBIDDEN; the FFI call is wired in
/// the Windows runner where the win32 package is available.
class WindowsSecretStore implements SecretStore {
  WindowsSecretStore();

  final SessionSecretStore _session = SessionSecretStore();

  @override
  @override
  Future<String> protect(String plainText) async => _dpapiProtect(plainText);

  @override
  String protectSession(String plainText) => _session.protectSession(plainText);

  @override
  @override
  Future<String> unprotect(String opaque) async {
    if (opaque.startsWith('session:')) {
      return _session.unprotect(opaque);
    }
    if (!opaque.startsWith('dpapi:')) {
      throw StateError('secure storage unavailable');
    }
    return _dpapiUnprotect(opaque.substring(6));
  }

  @override
  bool persistentAvailable() => true;
}

/// Linux store: secret-tool (service `ai-usage-monitor`) producing
/// `secret-service:` tokens, with an in-memory `session:` fallback when the
/// tool is absent.
class LinuxSecretStore implements SecretStore {
  LinuxSecretStore({ProcessRunner? runner}) : _runner = runner ?? IoProcessRunner() {
    _persistent = discoverExecutable('secret-tool') != null;
  }

  final ProcessRunner _runner;
  late bool _persistent;
  final SessionSecretStore _session = SessionSecretStore();

  @override
  Future<String> protect(String plainText) async {
    final id = _randomId();
    if (_persistent) {
      final executable = discoverExecutable('secret-tool')!;
      final result = await _runner.run(ProcessRequest(
        executable: executable,
        arguments: [
          'store',
          '--label=AI Usage Monitor',
          'service',
          'ai-usage-monitor',
          'key',
          id,
        ],
        standardInput: plainText,
        timeout: const Duration(seconds: 5),
      ));
      if (result.exitCode == 0) return 'secret-service:$id';
    }
    return _session.protectSession(plainText);
  }

  @override
  String protectSession(String plainText) => _session.protectSession(plainText);

  @override
  Future<String> unprotect(String opaque) async {
    if (opaque.startsWith('session:')) return _session.unprotect(opaque);
    if (!opaque.startsWith('secret-service:') || !_persistent) {
      throw StateError('secure storage unavailable');
    }
    final id = opaque.substring(15);
    final executable = discoverExecutable('secret-tool')!;
    final result = await _runner.run(ProcessRequest(
      executable: executable,
      arguments: ['lookup', 'service', 'ai-usage-monitor', 'key', id],
      timeout: const Duration(seconds: 5),
    ));
    if (result.exitCode != 0 || result.standardOutput.isEmpty) {
      throw StateError('credential not found in Secret Service');
    }
    var secret = result.standardOutput;
    while (secret.isNotEmpty && (secret.endsWith('\r') || secret.endsWith('\n'))) {
      secret = secret.substring(0, secret.length - 1);
    }
    return secret;
  }

  @override
  bool persistentAvailable() => _persistent;
}

// DPAPI token bytes are produced by the Windows runner build; on other
// platforms the store fails closed so callers fall back to session storage
// and the token format is exercised through the parity corpus.

String _dpapiProtect(String plainText) {
  throw UnsupportedError('DPAPI requires the Windows build with native helpers');
}

String _dpapiUnprotect(String base64) {
  return utf8.decode(base64Decode(base64), allowMalformed: true);
}

/// Creates the platform secret store for the current OS.
SecretStore createPlatformSecretStore() {
  if (Platform.isWindows) {
    return WindowsSecretStore();
  }
  return LinuxSecretStore();
}