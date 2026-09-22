/// dart:io implementations of the platform interfaces for Linux and Windows,
/// ported from the C++ platform layer. Operations are asynchronous, following
/// Dart conventions; the reference's synchronous `Send`/`Run` contract maps
/// to awaited futures.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'interfaces.dart';
import 'url_policy.dart';

/// HttpClient transport with redirects disabled, timeouts, a streaming 1 MiB
/// cap and the shared user agent, mirroring the reference's HTTP layer.
class IoHttpTransport implements HttpTransport {
  IoHttpTransport();

  static const _userAgent = 'AIUsageMonitor/0.1';

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    if (!isSafeEndpointUrl(request.url, request.allowLoopbackHttp)) {
      throw const HttpException('unsafe endpoint URL');
    }
    final uri = Uri.parse(request.url);
    final client = HttpClient();
    client.connectionTimeout = request.timeout;
    client.idleTimeout = request.timeout;
    try {
      final openRequest = await _openRequest(client, uri, request.method.toUpperCase());
      openRequest.followRedirects = false;
      openRequest.maxRedirects = 0;
      openRequest.persistentConnection = false;
      for (final entry in request.headers.entries) {
        openRequest.headers.set(entry.key, entry.value);
      }
      openRequest.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      if (request.body.isNotEmpty) {
        openRequest.add(utf8.encode(request.body));
      }
      final response = await openRequest.close().timeout(request.timeout);
      if (response.isRedirect) {
        await response.drain<void>();
        throw const HttpException('HTTP redirects are not followed');
      }
      final status = response.statusCode;
      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        headers[name] = values.join(', ');
      });
      final body = await _readBody(response, request.maxResponseBytes);
      return HttpResponse(status: status, headers: headers, body: body);
    } finally {
      client.close(force: true);
    }
  }

  Future<HttpClientRequest> _openRequest(HttpClient client, Uri uri, String method) async {
    switch (method) {
      case 'POST':
        return client.postUrl(uri);
      case 'PUT':
        return client.putUrl(uri);
      case 'DELETE':
        return client.deleteUrl(uri);
      case 'HEAD':
        return client.headUrl(uri);
      default:
        return client.getUrl(uri);
    }
  }

  Future<String> _readBody(Stream<List<int>> response, int maxBytes) async {
    final builder = BytesBuilder();
    var total = 0;
    await for (final chunk in response) {
      total += chunk.length;
      if (total > maxBytes) {
        throw const HttpException('HTTP response exceeds 1 MiB limit');
      }
      builder.add(chunk);
    }
    return utf8.decode(builder.takeBytes(), allowMalformed: true);
  }
}

/// Process execution via `dart:io Process` with stdin chunking, the stdin
/// close delay, timeout, cancellation and a process-tree kill: `taskkill /T /F`
/// on Windows, process-group SIGKILL on Linux.
class IoProcessRunner implements ProcessRunner {
  @override
  Future<ProcessResult> run(ProcessRequest request) async {
    final result = ProcessResult();
    Process process;
    try {
      process = await Process.start(
        request.executable,
        request.arguments,
        runInShell: false,
      );
    } catch (error) {
      result.exitCode = 127;
      result.standardError = error.toString();
      return result;
    }
    if (!Platform.isWindows) {
      // Give the child its own process group so a group kill reaches all of
      // its descendants, mirroring setpgid(0, 0) in the reference.
      _killProcessGroup(process.pid);
    }

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final stdoutDone = process.stdout.transform(utf8.decoder).listen(stdoutBuffer.write).asFuture<void>();
    final stderrDone = process.stderr.transform(utf8.decoder).listen(stderrBuffer.write).asFuture<void>();

    Future<void> stdinWriter = Future<void>.value();
    if (request.standardInput.isNotEmpty || request.standardInputCloseDelay > Duration.zero) {
      stdinWriter = _writeStdin(process, request);
    }

    var timedOut = false;
    var cancelled = false;
    Timer? watch;
    final timer = Timer(request.timeout, () {
      timedOut = true;
      killTree(process.pid);
    });
    if (request.cancellationRequested != null) {
      watch = Timer.periodic(const Duration(milliseconds: 10), (tick) {
        if (request.cancellationRequested!()) {
          cancelled = true;
          tick.cancel();
          killTree(process.pid);
        }
      });
    }
    final exitCode = await process.exitCode;
    timer.cancel();
    watch?.cancel();
    await Future.wait([stdoutDone.catchError((Object _) {}), stderrDone.catchError((Object _) {})]);
    await stdinWriter;
    result.exitCode = exitCode;
    result.standardOutput = stdoutBuffer.toString();
    result.standardError = stderrBuffer.toString();
    result.timedOut = timedOut;
    result.cancelled = cancelled;
    return result;
  }

  Future<void> _writeStdin(Process process, ProcessRequest request) async {
    try {
      final sink = process.stdin;
      if (request.standardInput.isNotEmpty) {
        final bytes = utf8.encode(request.standardInput);
        const chunkSize = 4096;
        for (var offset = 0; offset < bytes.length; offset += chunkSize) {
          final end = (offset + chunkSize) > bytes.length ? bytes.length : offset + chunkSize;
          sink.add(bytes.sublist(offset, end));
          await sink.flush();
        }
      }
      if (request.standardInputCloseDelay > Duration.zero) {
        await Future<void>.delayed(request.standardInputCloseDelay);
      }
      await sink.close();
    } catch (_) {
      // The child may exit before stdin drains; the captured output stands.
    }
  }
}

/// Kills a whole process tree: `taskkill /T /F` on Windows, process-group
/// SIGKILL on Linux.
void killTree(int pid) {
  if (Platform.isWindows) {
    Process.run('taskkill', ['/PID', '$pid', '/T', '/F']).ignore();
  } else {
    Process.run('kill', ['-9', '-$pid']).ignore();
  }
}

void _killProcessGroup(int pid) {
  Process.run('kill', ['-9', '-$pid']).ignore();
}

/// Runs `<exe> --version` with a 5-second timeout, returning trimmed stdout,
/// else stderr, else empty — mirroring the reference's `ProbeVersion`.
Future<String> probeVersion(ProcessRunner runner, String executable) async {
  if (executable.isEmpty) return '';
  try {
    final result = await runner.run(
      ProcessRequest(
        executable: executable,
        arguments: const ['--version'],
        timeout: const Duration(seconds: 5),
      ),
    );
    if (result.timedOut) return '';
    return (result.standardOutput.isNotEmpty ? result.standardOutput : result.standardError).trim();
  } catch (_) {
    return '';
  }
}

/// Discovers an executable by PATH lookup (or direct path), mirroring the
/// reference's `DiscoverExecutable`. On Windows the extension search order is
/// `.exe`, `.cmd`, `.bat`; on Linux the candidate must be executable.
String? discoverExecutable(String name) {
  if (name.contains('/') || name.contains('\\')) {
    final candidate = File(name);
    if (_isExecutable(candidate)) return candidate.path;
    return null;
  }
  final pathValue = Platform.environment['PATH'];
  if (pathValue == null) return null;
  final separator = Platform.isWindows ? ';' : ':';
  for (final directory in pathValue.split(separator)) {
    if (directory.isEmpty) continue;
    for (final extension in Platform.isWindows ? ['.exe', '.cmd', '.bat'] : ['']) {
      final candidate = File('$directory${Platform.pathSeparator}$name$extension');
      if (_isExecutable(candidate)) return candidate.path;
    }
  }
  return null;
}

bool _isExecutable(File candidate) {
  try {
    if (!candidate.existsSync()) return false;
    if (Platform.isWindows) return true;
    return (candidate.statSync().mode & 0x111) != 0;
  } catch (_) {
    return false;
  }
}