## Purpose

Define the provider monitoring behavior of the Flutter application so that, for the same configuration and the same provider responses, it produces exactly the same normalized snapshots, metrics, errors and refresh scheduling as the C++ reference application.

## ADDED Requirements

### Requirement: Identical provider coverage
The Flutter application SHALL support the provider kinds `codex`, `claude-subscription`, `deepseek`, `openai-compatible` and `ollama`, and SHALL produce snapshots with the same provider identifier, display name, kind, freshness, health, metrics, account label and error as the reference application for the same inputs.

#### Scenario: Same provider list produces same normalized output
- **WHEN** both applications refresh the same configured providers with the same responses
- **THEN** each normalized snapshot matches field by field, including metric kind, value, unit, scope, provenance, availability, label, reset time and window

#### Scenario: Unknown provider kind
- **WHEN** a provider kind outside the supported set is requested
- **THEN** the refresh fails with an unsupported-kind error and no invented metrics

### Requirement: Codex app-server integration
The Flutter application SHALL obtain Codex data by running the configured `codex` executable with arguments `app-server --listen stdio://`, writing the same five JSONL requests as the reference (initialize with client name `ai-usage-monitor`, title `AI Usage Monitor`, version `0.1.1`; initialized; `account/read` with `refreshToken` false; `account/rateLimits/read`; `account/usage/read`), keeping stdin open for 3000 ms, and parsing one JSON object per non-empty line with the same rules, labels and error mapping.

#### Scenario: Account and rate limits are published
- **WHEN** the app-server returns an account with an e-mail and rate-limit buckets with `usedPercent`, `resetsAt` and `windowDurationMins`
- **THEN** the snapshot shows the account label, a used and a derived remaining percentage per window bucket, and a lifetime token metric when the summary publishes `lifetimeTokens`

#### Scenario: Malformed or missing responses
- **WHEN** a line is malformed, a protocol error object is present, the account result is missing, or the account is unauthenticated
- **THEN** the application reports the same protocol or authentication error as the reference and invents no quota

#### Scenario: App-server times out
- **WHEN** the app-server does not return before the refresh timeout
- **THEN** the refresh fails with the same timeout error and no partial metrics

### Requirement: Claude local usage integration
The Flutter application SHALL obtain Claude data by running the configured `claude` executable with argument `/usage`, without prompts or API calls, and SHALL strip ANSI/OSC sequences, apply backspace and control-character handling, and parse session and week percentages and reset times using the same patterns, thresholds and labels as the reference.

#### Scenario: Session and week quotas are parsed
- **WHEN** `claude /usage` prints current session and current week percentages with `used`/`usado` and a resets line
- **THEN** the snapshot contains session and week used and derived remaining percentages with the parsed reset time

#### Scenario: Percentage exceeds one hundred
- **WHEN** a parsed percentage is greater than 100
- **THEN** the parse fails closed and the refresh reports an unsupported-output error rather than clamping or inventing a value

#### Scenario: Command fails
- **WHEN** the executable is missing, exits non-zero, is cancelled or times out
- **THEN** the refresh reports the matching error and preserves any previous valid metrics as stale

### Requirement: DeepSeek balance integration
The Flutter application SHALL query the configured or default `https://api.deepseek.com` `GET /user/balance` with a Bearer credential and `Accept: application/json`, and SHALL parse `is_available` and `balance_infos` into per-currency balance metrics with unit `USD` or `CNY` (otherwise `Unknown`), plus an unsupported token metric and an optional derived spent metric when a budget is configured.

#### Scenario: Balance is available
- **WHEN** the endpoint returns `is_available` true and one or more balance entries
- **THEN** each entry becomes a current-balance metric with its currency unit and the snapshot is healthy

#### Scenario: Balance is not available
- **WHEN** `is_available` is false
- **THEN** the snapshot is partial with a `balance-unavailable` error and still shows the reported balances

#### Scenario: Missing credential or schema
- **WHEN** no API key is configured or `is_available`/`balance_infos` is missing
- **THEN** the refresh fails with the matching required-key or schema error and produces no balance metrics

### Requirement: OpenAI-compatible mappings
The Flutter application SHALL support configurable usage and balance routes and up to 16 JSON Pointer mappings, and SHALL emit metrics in the reference order (`used_percent`, `remaining_percent`, `total_tokens`, `balance_usd`, `balance_cny`, `spent_usd`) with the reference kinds, units, scopes and labels, failing the whole refresh when a configured pointer is absent.

#### Scenario: Configured pointers resolve
- **WHEN** the response contains every configured JSON Pointer
- **THEN** the snapshot contains the corresponding metrics in the reference order and is healthy

#### Scenario: A pointer is missing
- **WHEN** the endpoint omits a value for a configured pointer
- **THEN** the refresh fails with the missing-pointer error and no partial metrics

#### Scenario: No route is configured
- **WHEN** neither a usage nor a balance route is configured and the connection test succeeds
- **THEN** the snapshot is partial with the reference unsupported balance and usage placeholders

### Requirement: Ollama local and cloud integration
The Flutter application SHALL query `GET <base>/api/ps` (optionally `POST <base>/api/me` for the account label) and, only when an ollama.com credential is stored, `GET https://ollama.com/api/usage`, producing loaded-model count, per-model memory and unload time, optional account label, and monthly used/remaining percentage plus per-model request counts, without inventing token, spend or currency figures.

#### Scenario: Models are loaded
- **WHEN** `/api/ps` returns running models with `size_vram` and a future `expires_at`
- **THEN** the snapshot reports the loaded count, each model name with its byte size and unload time, and no percentage quota

#### Scenario: Cloud credits are reported
- **WHEN** an ollama.com key is stored and `/api/usage` returns a `0..1` monthly fraction with per-model request counts
- **THEN** the snapshot shows used and remaining percentages and each model's request count, with no currency amount

#### Scenario: Cloud lookup fails or no cloud key exists
- **WHEN** `/api/usage` is unreachable or rejects the credential, or no ollama.com key is stored
- **THEN** the local observation is preserved, the snapshot degrades to partial when a lookup was attempted, and no credit figure is invented

#### Scenario: Credential separation
- **WHEN** the provider holds both a local server credential and an ollama.com credential
- **THEN** the local credential is sent only to the configured base URL and the cloud credential only to `ollama.com`

### Requirement: Reference refresh scheduling and backoff
The Flutter application SHALL refresh on a 1-to-60-minute interval (default 5), support manual refresh of all or one provider, allow at most two concurrent refreshes, coalesce queued refreshes, and apply the reference exponential backoff with deterministic per-provider jitter, honoring a server `Retry-After` when larger.

#### Scenario: Interval is applied
- **WHEN** the configured interval is saved
- **THEN** each provider refreshes on that interval and a manual refresh runs immediately

#### Scenario: A provider keeps failing
- **WHEN** a refresh fails repeatedly
- **THEN** the next attempt is delayed by the reference backoff sequence with deterministic jitter, capped at 60 minutes, and a `Retry-After` value overrides upward

#### Scenario: A provider recovers
- **WHEN** a previously failing provider returns a non-error result
- **THEN** its failure count resets and it returns to the configured interval

### Requirement: Snapshot lifecycle and stale preservation
The Flutter application SHALL, on a refresh error for a provider that already has valid metrics, retain those metrics and mark them stale with the new error, SHALL mark in-flight refreshes with the `refreshing` notice, SHALL show a `waiting` placeholder before the first data, and SHALL write only snapshots with metrics to the cache.

#### Scenario: Refresh fails after a valid snapshot
- **WHEN** a provider that already published valid metrics fails its next refresh
- **THEN** the cached metrics remain visible, marked stale, carrying the new error

#### Scenario: Manual refresh in progress
- **WHEN** the user triggers a refresh
- **THEN** affected providers show the `refreshing` notice and the previous values remain visible until new data arrives

#### Scenario: Startup before first refresh
- **WHEN** the application starts with cached data
- **THEN** it shows that data as stale until the first refresh completes
