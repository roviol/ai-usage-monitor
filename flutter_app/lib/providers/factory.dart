/// Provider factory creating the adapter for a configured provider kind.
library;

import '../config/settings.dart';
import '../domain/model.dart';
import '../platform/interfaces.dart';
import 'claude.dart';
import 'codex.dart';
import 'deepseek.dart';
import 'ollama.dart';
import 'openai_compatible.dart';
import 'provider.dart';

/// Unsupported kinds are rejected rather than inventing a provider.
UsageProvider createProvider(
  ProviderConfig config,
  HttpTransport http,
  ProcessRunner process,
  SecretStore secrets,
  Clock clock,
) {
  switch (config.kind) {
    case ProviderKind.codex:
      return CodexProvider(config, process, clock);
    case ProviderKind.claudeSubscription:
      return ClaudeSubscriptionProvider(config, process, clock);
    case ProviderKind.deepSeek:
      return DeepSeekProvider(config, http, secrets, clock);
    case ProviderKind.openAiCompatible:
      return GenericProvider(config, http, secrets, clock);
    case ProviderKind.ollama:
      return OllamaProvider(config, http, secrets, clock);
  }
}