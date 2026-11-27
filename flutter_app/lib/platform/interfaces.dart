/// Platform abstraction interfaces plus in-memory fakes for tests.
///
/// Mirrors the C++ `IHttpClient`/`IProcessRunner`/`ISecretStore`/
/// `ISingleInstanceSignal`/`IClock` layer.
library;

import 'dart:async';

abstract class HttpTransport {
  Future<HttpResponse> send(HttpRequest request);
}

/// One outbound HTTP request. `allowLoopbackHttp` participates in the URL
/// safety policy enforced by real transports.
class HttpRequest {
  HttpRequest({
    this.method = 'GET',
    this.url = '',
    Map<String, String>? headers,
    this.body = '',
    this.timeout = const Duration(seconds: 10),
    this.maxResponseBytes = 1024 * 1024,
    this.allowLoopbackHttp = false,
  }) : headers = headers ?? <String, String>{};

  String method;
  String url;
  final Map<String, String> headers;
  String body;
  Duration timeout;
  int maxResponseBytes;
  bool allowLoopbackHttp;
}

/// One completed HTTP exchange.
class HttpResponse {
  HttpResponse({this.status = 0, Map<String, String>? headers, this.body = ''})
      : headers = headers ?? <String, String>{};

  int status;
  final Map<String, String> headers;
  String body;
}

/// One child process execution request.
class ProcessRequest {
  ProcessRequest({
    required this.executable,
    this.arguments = const [],
    this.standardInput = '',
    this.timeout = const Duration(seconds: 10),
    this.cancellationRequested,
    this.standardInputCloseDelay = Duration.zero,
  });

  final String executable;
  final List<String> arguments;
  final String standardInput;
  final Duration timeout;
  final bool Function()? cancellationRequested;

  /// Some stdio servers need stdin to remain open while they process JSONL
  /// requests (Codex app-server uses 3000 ms).
  final Duration standardInputCloseDelay;
}

class ProcessResult {
  ProcessResult({
    this.exitCode = -1,
    this.standardOutput = '',
    this.standardError = '',
    this.timedOut = false,
    this.cancelled = false,
  });

  int exitCode;
  String standardOutput;
  String standardError;
  bool timedOut;
  bool cancelled;
}

abstract class ProcessRunner {
  Future<ProcessResult> run(ProcessRequest request);
}

abstract class SecretStore {
  Future<String> protect(String plainText);
  String protectSession(String plainText);
  Future<String> unprotect(String opaque);
  bool persistentAvailable();
}

abstract class Clock {
  DateTime now();
}

abstract class SingleInstanceSignal {
  bool isAnotherRunning();
  void signalActivation();
  bool consumeActivation();
  Future<bool> waitForActivation(Duration timeout);
}

/// One connected monitor with work-area geometry in logical pixels.
class MonitorInfo {
  MonitorInfo({
    required this.id,
    required this.isPrimary,
    required this.workAreaLeft,
    required this.workAreaTop,
    required this.workAreaWidth,
    required this.workAreaHeight,
  });

  final String id;
  final bool isPrimary;
  final int workAreaLeft;
  final int workAreaTop;
  final int workAreaWidth;
  final int workAreaHeight;
}

/// Monitor enumeration service; the reference identifiers
/// (`\\.\DISPLAYn` on Windows, display name or `display-N` on Linux) are the
/// persisted contract.
abstract class MonitorService {
  List<MonitorInfo> monitors();

  /// The primary monitor, or a fallback monitor when none is detectable.
  MonitorInfo? primary();
}

/// Fake clock advancing only when told to.
class FakeClock implements Clock {
  FakeClock([DateTime? initial]) : _now = initial ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  DateTime _now;

  void advance(Duration duration) => _now = _now.add(duration);

  @override
  DateTime now() => _now;
}

/// Records requests and replays queued responses/errors.
class FakeHttpTransport implements HttpTransport {
  FakeHttpTransport();

  final List<HttpRequest> requests = [];
  final List<Future<HttpResponse> Function(HttpRequest)> handlers = [];

  void enqueue(Future<HttpResponse> Function(HttpRequest) handler) => handlers.add(handler);

  void enqueueResponse(int status, String body, {Map<String, String>? headers}) =>
      enqueue((_) async => HttpResponse(status: status, headers: headers ?? {}, body: body));

  @override
  Future<HttpResponse> send(HttpRequest request) {
    requests.add(request);
    if (handlers.isEmpty) {
      throw StateError('FakeHttpTransport has no queued handler');
    }
    return handlers.removeAt(0)(request);
  }
}

/// Records process requests and replays queued results.
class FakeProcessRunner implements ProcessRunner {
  FakeProcessRunner();

  final List<ProcessRequest> requests = [];
  final List<ProcessResult> results = [];

  void enqueue(ProcessResult result) => results.add(result);

  @override
  Future<ProcessResult> run(ProcessRequest request) {
    requests.add(request);
    if (results.isEmpty) {
      throw StateError('FakeProcessRunner has no queued result');
    }
    return Future.value(results.removeAt(0));
  }
}

/// Session-only secret store fake emitting `session:` tokens.
class FakeSecretStore implements SecretStore {
  FakeSecretStore({this.persistent = false});

  bool persistent;
  final Map<String, String> _session = {};
  final Map<String, String> _persistent = {};
  int _counter = 0;

  @override
  Future<String> protect(String plainText) async {
    if (persistent) {
      final id = _nextId();
      _persistent[id] = plainText;
      return 'secret-service:$id';
    }
    return protectSession(plainText);
  }

  @override
  String protectSession(String plainText) {
    final id = _nextId();
    _session[id] = plainText;
    return 'session:$id';
  }

  @override
  Future<String> unprotect(String opaque) async {
    if (opaque.startsWith('session:')) {
      final secret = _session[opaque.substring(8)];
      if (secret == null) throw StateError('session-only credential expired');
      return secret;
    }
    if (opaque.startsWith('secret-service:')) {
      final secret = _persistent[opaque.substring(15)];
      if (secret == null) throw StateError('credential not found');
      return secret;
    }
    if (opaque.startsWith('dpapi:')) {
      final secret = _persistent[opaque.substring(6)];
      if (secret == null) throw StateError('credential not found');
      return secret;
    }
    throw StateError('secure storage unavailable');
  }

  @override
  bool persistentAvailable() => persistent;

  String _nextId() => (_counter++).toRadixString(16).padLeft(8, '0');
}

/// Records activation signaling without any real synchronization.
class FakeSingleInstanceSignal implements SingleInstanceSignal {
  FakeSingleInstanceSignal({bool anotherRunning = false}) : _anotherRunning = anotherRunning;

  final bool _anotherRunning;
  bool activated = false;
  final List<Duration> waitTimeouts = [];

  @override
  bool isAnotherRunning() => _anotherRunning;

  @override
  void signalActivation() => activated = true;

  @override
  bool consumeActivation() {
    final value = activated;
    activated = false;
    return value;
  }

  @override
  Future<bool> waitForActivation(Duration timeout) async {
    waitTimeouts.add(timeout);
    await Future<void>.delayed(Duration.zero);
    return consumeActivation();
  }
}

/// Single fallback monitor used when enumeration is unavailable.
class FakeMonitorService implements MonitorService {
  FakeMonitorService({List<MonitorInfo>? monitors, MonitorInfo? primary})
      : _monitors = monitors,
        _primary = primary;

  List<MonitorInfo>? _monitors;
  final MonitorInfo? _primary;

  set monitorList(List<MonitorInfo>? value) => _monitors = value;

  @override
  List<MonitorInfo> monitors() => _monitors ?? <MonitorInfo>[];

  @override
  MonitorInfo? primary() => _primary ?? (_monitors != null && _monitors!.isNotEmpty ? _monitors!.first : null);
}

/// Fixed system clock.
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}