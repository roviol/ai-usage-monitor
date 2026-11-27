/// Provider interface shared by all adapters, mirroring `IUsageProvider`.
library;

import '../config/settings.dart';
import '../domain/model.dart';

/// Capability summary surfaced by connection tests.
class ProviderCapabilities {
  const ProviderCapabilities({
    this.usage = false,
    this.remaining = false,
    this.balance = false,
    this.tokenActivity = false,
    this.detail = '',
  });

  final bool usage;
  final bool remaining;
  final bool balance;
  final bool tokenActivity;
  final String detail;
}

/// Result of a settings-window connection test.
class ConnectionTestResult {
  const ConnectionTestResult({required this.success, required this.capabilities, required this.message});

  final bool success;
  final ProviderCapabilities capabilities;
  final String message;
}

abstract class UsageProvider {
  ProviderConfig get config;

  ProviderCapabilities capabilities();

  Future<ConnectionTestResult> testConnection();

  Future<ProviderSnapshot> refresh();

  void cancel();
}