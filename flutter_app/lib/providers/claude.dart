/// Claude adapter: runs `claude /usage` locally without prompts or API
/// calls, strips ANSI/OSC sequences, applies backspace/control handling and
/// parses session and week percentages plus reset times.
library;

import '../config/settings.dart';
import '../domain/decimal.dart';
import '../domain/model.dart';
import '../platform/interfaces.dart';
import 'base.dart';
import 'provider.dart';
import 'provider_exception.dart';

final RegExp _percentagePattern = RegExp(
  r'(Current session|Current week(?: \(all models\))?)[^0-9\n]{0,40}([0-9]{1,3})%[^\n]*(?:used|usado)[^\n]*',
  caseSensitive: false,
);

final RegExp _resetPattern = RegExp(
  r'\b(?:resets|reinicia)\s+([A-Za-z]{3})\s+([0-9]{1,2}),?\s+([0-9]{1,2})(?::([0-9]{2}))?\s*(am|pm)\b',
  caseSensitive: false,
);

const List<String> _months = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];

/// Strips ANSI/OSC sequences, backspaces and control characters, converting
/// CR to LF like the reference's `PlainTerminalText`.
String plainTerminalText(String terminal) {
  final plain = StringBuffer();
  var index = 0;
  while (index < terminal.length) {
    final character = terminal.codeUnitAt(index);
    if (character == 0x1B) {
      index++;
      if (index < terminal.length && terminal.codeUnitAt(index) == 0x5B) {
        // CSI: consume until a byte in 0x40..0x7E terminates it.
        index++;
        while (index < terminal.length) {
          final marker = terminal.codeUnitAt(index++);
          if (marker >= 0x40 && marker <= 0x7E) break;
        }
      } else if (index < terminal.length && terminal.codeUnitAt(index) == 0x5D) {
        // OSC: consume until BEL or ST.
        index++;
        while (index < terminal.length) {
          if (terminal.codeUnitAt(index) == 0x07) {
            index++;
            break;
          }
          if (terminal.codeUnitAt(index) == 0x1B &&
              index + 1 < terminal.length &&
              terminal.codeUnitAt(index + 1) == 0x5C) {
            index += 2;
            break;
          }
          index++;
        }
      } else if (index < terminal.length) {
        index++;
      }
      continue;
    }
    if (character == 0x08) {
      final text = plain.toString();
      if (text.isNotEmpty) {
        plain.clear();
        plain.write(text.substring(0, text.length - 1));
      }
      index++;
      continue;
    }
    if (character == 0x0D) {
      plain.write('\n');
      index++;
      continue;
    }
    if (character < 0x20 && character != 0x0A && character != 0x09) {
      index++;
      continue;
    }
    plain.writeCharCode(character);
    index++;
  }
  return plain.toString();
}

int? _monthIndex(String month) {
  final lowered = month.toLowerCase();
  final index = _months.indexOf(lowered);
  return index == -1 ? null : index;
}

/// Parses `resets Mon 5, 7:10pm` lines in the local timezone like the
/// reference's `ParseClaudeReset`, rolling to the next year when the date
/// already passed and rejecting non-existing calendar dates.
DateTime? parseClaudeReset(String line, DateTime observedAt) {
  final match = _resetPattern.firstMatch(line);
  if (match == null) return null;
  final month = _monthIndex(match.group(1)!);
  if (month == null) return null;
  final day = int.parse(match.group(2)!);
  var hour = int.parse(match.group(3)!);
  final minute = match.group(4) != null ? int.parse(match.group(4)!) : 0;
  final meridiem = match.group(5)!.toLowerCase();
  if (day < 1 || day > 31 || hour < 1 || hour > 12 || minute < 0 || minute > 59) return null;
  if (hour == 12) hour = 0;
  if (meridiem == 'pm') hour += 12;

  final localNow = observedAt.toLocal();
  var candidate = DateTime(localNow.year, month + 1, day, hour, minute, 0);
  var result = candidate;
  if (result.isBefore(observedAt)) {
    candidate = DateTime(localNow.year + 1, month + 1, day, hour, minute, 0);
    result = candidate;
  }
  if (result.month != month + 1 || result.day != day || result.hour != hour || result.minute != minute) {
    return null;
  }
  return result.toUtc();
}

class ClaudeSubscriptionProvider extends UsageProvider {
  ClaudeSubscriptionProvider(this._config, this._process, this._clock);

  final ProviderConfig _config;
  final ProcessRunner _process;
  final Clock _clock;
  bool _cancelled = false;

  @override
  ProviderConfig get config => _config;

  @override
  void cancel() => _cancelled = true;

  @override
  ProviderCapabilities capabilities() => const ProviderCapabilities(
        usage: true,
        remaining: true,
        detail: 'claude /usage local no interactivo',
      );

  @override
  Future<ConnectionTestResult> testConnection() async {
    try {
      final snapshot = await refresh();
      return ConnectionTestResult(
        success: snapshot.health == Health.healthy,
        capabilities: capabilities(),
        message: 'claude /usage disponible',
      );
    } on ProviderException catch (error) {
      return ConnectionTestResult(success: false, capabilities: capabilities(), message: error.error.message);
    } catch (error) {
      return ConnectionTestResult(success: false, capabilities: capabilities(), message: error.toString());
    }
  }

  @override
  Future<ProviderSnapshot> refresh() async {
    _cancelled = false;
    if (_config.executable.isEmpty) {
      throw ProviderException(ProviderError('refresh-failed', 'Claude executable unavailable', transient: true));
    }
    final result = await _process.run(ProcessRequest(
      executable: _config.executable,
      arguments: const ['/usage'],
      timeout: const Duration(seconds: 10),
      cancellationRequested: () => _cancelled,
    ));
    if (result.cancelled) {
      throw ProviderException(ProviderError('cancelled', 'claude /usage cancelled', transient: true));
    }
    if (result.timedOut) {
      throw ProviderException(ProviderError('timeout', 'claude /usage timed out', transient: true));
    }
    if (result.exitCode != 0) {
      throw ProviderException(
        ProviderError('refresh-failed', 'claude /usage failed: ${result.standardError}', transient: true),
      );
    }
    final parsed = parseClaudeUsageText(_config, result.standardOutput, _clock.now());
    if (parsed == null) {
      throw ProviderException(
        ProviderError('unsupported-output', 'claude /usage output schema is unsupported', transient: true),
      );
    }
    return parsed;
  }
}

/// Parses the cleaned terminal text into session/week percentages.
ProviderSnapshot? parseClaudeUsageText(ProviderConfig config, String output, DateTime observedAt) {
  final plain = plainTerminalText(output);
  final snapshot = baseSnapshot(config, observedAt);
  for (final match in _percentagePattern.allMatches(plain)) {
    final used = match.group(2)!;
    if (int.parse(used) > 100) return null;
    final period = match.group(1)!;
    final weekly = period.toLowerCase().contains('week');
    final label = weekly ? 'Claude semana' : 'Claude sesión';
    final reset = parseClaudeReset(match.group(0)!, observedAt);
    snapshot.metrics.add(Metric(
      kind: MetricKind.usedPercent,
      value: used,
      unit: MetricUnit.percent,
      scope: MetricScope.rollingWindow,
      provenance: Provenance.cliBridge,
      availability: Availability.available,
      resetsAt: reset,
      label: '$label usado',
    ));
    snapshot.metrics.add(Metric(
      kind: MetricKind.remainingPercent,
      value: subtractDecimals('100', used),
      unit: MetricUnit.percent,
      scope: MetricScope.rollingWindow,
      provenance: Provenance.derived,
      availability: Availability.available,
      resetsAt: reset,
      label: '$label restante',
    ));
  }
  if (snapshot.metrics.isEmpty) return null;
  return snapshot;
}