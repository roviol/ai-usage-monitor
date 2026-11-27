import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_usage_monitor/platform/platform.dart';

void main() {
  group('isSafeEndpointUrl', () {
    test('https is always accepted', () {
      expect(isSafeEndpointUrl('https://api.deepseek.com/user/balance', false), isTrue);
      expect(isSafeEndpointUrl('https://example.com', false), isTrue);
      expect(isSafeEndpointUrl('HTTPS://EXAMPLE.COM', false), isTrue);
    });

    test('remote http is rejected without exception', () {
      expect(isSafeEndpointUrl('http://example.com', false), isFalse);
      expect(isSafeEndpointUrl('http://example.com', true), isFalse);
      expect(isSafeEndpointUrl('http://192.168.1.10', true), isFalse);
    });

    test('loopback http requires the exception', () {
      expect(isSafeEndpointUrl('http://localhost:11434', false), isFalse);
      expect(isSafeEndpointUrl('http://localhost:11434', true), isTrue);
      expect(isSafeEndpointUrl('http://127.0.0.1:11434', true), isTrue);
      expect(isSafeEndpointUrl('http://[::1]:11434', true), isTrue);
      // The bare `::1` form never matches the URL pattern, mirroring the
      // reference's regex-based host extraction.
      expect(isSafeEndpointUrl('http://::1', true), isFalse);
    });

    test('malformed urls are rejected', () {
      expect(isSafeEndpointUrl('not a url', false), isFalse);
      expect(isSafeEndpointUrl('ftp://example.com', false), isFalse);
      expect(isSafeEndpointUrl('', false), isFalse);
    });

    test('constant limit matches the reference', () {
      expect(maxHttpResponseBytes, 1024 * 1024);
    });
  });

  group('redactSecrets', () {
    test('replaces secrets and authorization headers', () {
      expect(redactSecrets('key=abc123', ['abc123']), 'key=<redacted>');
      expect(
        redactSecrets('Authorization: Bearer sk-123', []),
        'Authorization: <redacted>',
      );
      expect(redactSecrets('nothing here', []), 'nothing here');
      expect(redactSecrets('a-b', ['', 'b']), 'a-<redacted>');
    });
  });

  group('FakeHttpTransport', () {
    test('queues responses in order', () async {
      final http = FakeHttpTransport();
      http.enqueueResponse(200, 'first');
      http.enqueueResponse(500, 'second');
      expect((await http.send(HttpRequest(url: 'https://x'))).body, 'first');
      expect((await http.send(HttpRequest(url: 'https://x'))).body, 'second');
      expect(http.requests, hasLength(2));
    });

    test('records requests', () async {
      final http = FakeHttpTransport();
      http.enqueueResponse(200, 'ok');
      await http.send(HttpRequest(url: 'https://example.com/api', method: 'POST', body: 'hi'));
      expect(http.requests.single.url, 'https://example.com/api');
      expect(http.requests.single.body, 'hi');
    });
  });

  group('FakeProcessRunner', () {
    test('replays queued results', () async {
      final runner = FakeProcessRunner();
      runner.enqueue(ProcessResult(exitCode: 0, standardOutput: 'v1.2'));
      runner.enqueue(ProcessResult(exitCode: 1, standardError: 'boom'));
      final first = await runner.run(ProcessRequest(executable: 'x'));
      final second = await runner.run(ProcessRequest(executable: 'x'));
      expect(first.standardOutput, 'v1.2');
      expect(second.standardError, 'boom');
    });
  });

  group('FakeSecretStore', () {
    test('session round trips', () async {
      final store = FakeSecretStore();
      final token = store.protectSession('secret');
      expect(token, startsWith('session:'));
      expect(await store.unprotect(token), 'secret');
    });

    test('persistent tokens round trip when enabled', () async {
      final store = FakeSecretStore(persistent: true);
      final token = await store.protect('secret');
      expect(token, startsWith('secret-service:'));
      expect(store.persistentAvailable(), isTrue);
      expect(await store.unprotect(token), 'secret');
    });

    test('unknown tokens fail', () {
      final store = FakeSecretStore();
      expect(() => store.unprotect('session:nope'), throwsStateError);
      expect(() => store.unprotect('dpapi:nope'), throwsStateError);
    });
  });

  group('FakeSingleInstanceSignal', () {
    test('activation round trip', () async {
      final signal = FakeSingleInstanceSignal();
      expect(signal.isAnotherRunning(), isFalse);
      signal.signalActivation();
      expect(await signal.waitForActivation(const Duration(milliseconds: 1)), isTrue);
      expect(signal.consumeActivation(), isFalse);
    });

    test('second instance reports another running', () {
      final signal = FakeSingleInstanceSignal(anotherRunning: true);
      expect(signal.isAnotherRunning(), isTrue);
    });
  });

  group('FakeMonitorService', () {
    test('falls back to first monitor as primary', () {
      final monitors = FakeMonitorService(
        monitors: [
          MonitorInfo(
            id: r'\\.\DISPLAY2',
            isPrimary: false,
            workAreaLeft: 0,
            workAreaTop: 0,
            workAreaWidth: 1920,
            workAreaHeight: 1080,
          ),
        ],
      );
      expect(monitors.primary()!.id, r'\\.\DISPLAY2');
    });

    test('empty enumeration has no primary', () {
      expect(FakeMonitorService().primary(), isNull);
    });
  });

  group('probeVersion', () {
    test('returns trimmed stdout', () async {
      final runner = FakeProcessRunner()..enqueue(ProcessResult(exitCode: 0, standardOutput: 'codex 0.1.1\n'));
      expect(await probeVersion(runner, 'codex'), 'codex 0.1.1');
    });

    test('falls back to stderr', () async {
      final runner = FakeProcessRunner()..enqueue(ProcessResult(exitCode: 0, standardError: 'claude 1.0\n'));
      expect(await probeVersion(runner, 'claude'), 'claude 1.0');
    });

    test('empty executable returns empty', () async {
      expect(await probeVersion(FakeProcessRunner(), ''), '');
    });

    test('timeout returns empty', () async {
      final runner = FakeProcessRunner()..enqueue(ProcessResult(timedOut: true));
      expect(await probeVersion(runner, 'codex'), '');
    });
  });

  group('discoverExecutable', () {
    test('finds a file in a temporary directory', () {
      final temp = Directory.systemTemp.createTempSync('discover');
      addTearDown(() => temp.deleteSync(recursive: true));
      final exe = File('${temp.path}${Platform.pathSeparator}toolx')..writeAsStringSync('#!/bin/sh\n');
      if (!Platform.isWindows) {
        Process.runSync('chmod', ['+x', exe.path]);
      }
      expect(discoverExecutable(exe.path), exe.path);
    });

    test('returns null for missing names', () {
      expect(discoverExecutable('definitely-not-a-tool-xyz-12345'), isNull);
    });
  });

  group('selectOverlayMonitor', () {
    test('saved monitor wins when available', () {
      expect(
        selectOverlayMonitor(r'\\.\DISPLAY2', [r'\\.\DISPLAY1', r'\\.\DISPLAY2'], r'\\.\DISPLAY1'),
        r'\\.\DISPLAY2',
      );
    });

    test('falls back to primary then first', () {
      expect(selectOverlayMonitor('gone', ['display-1', 'display-2'], 'display-2'), 'display-2');
      expect(selectOverlayMonitor('gone', ['display-1'], ''), 'display-1');
      expect(selectOverlayMonitor('', [], ''), '');
    });
  });

  group('FakeClock', () {
    test('advances on demand', () {
      final clock = FakeClock();
      expect(clock.now(), DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
      clock.advance(const Duration(minutes: 5));
      expect(clock.now(), DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).add(const Duration(minutes: 5)));
    });
  });
}