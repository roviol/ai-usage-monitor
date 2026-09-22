## Purpose

Define the persistence, configuration validation, credential protection and URL safety behavior of the Flutter application so that it can safely share `settings.json` and `cache.json` with the C++ reference application and preserve user data across both.

## ADDED Requirements

### Requirement: Shared settings file contract
The Flutter application SHALL read and write `settings.json` with the same schema, field names, serialization shape and defaults as the reference application: `schemaVersion` (required, currently 1), `refreshMinutes` (default 5), `alwaysOnTop` (default false), `overlay` and `providers` (default empty array). Unknown or missing fields SHALL be rejected as the reference does.

#### Scenario: Reference settings file is opened
- **WHEN** the Flutter application loads a settings file written by the C++ application
- **THEN** all providers, preferences, overlay settings and protected credentials are restored with identical meaning

#### Scenario: Flutter settings file is opened by reference
- **WHEN** the C++ application loads a settings file written by the Flutter application
- **THEN** it parses it without error and restores the same configuration

#### Scenario: Settings contain an unknown field
- **WHEN** a settings file contains a field the schema does not define or omits a required one
- **THEN** loading fails as the reference does and recovery uses the `.bak` copy when present

### Requirement: Shared cache file contract
The Flutter application SHALL read and write `cache.json` with the same `schemaVersion`, snapshot and metric field names and value encodings as the reference, SHALL load on startup with freshness forced to stale and healthy health downgraded to partial, and SHALL exclude invalid or metric-less snapshots when saving.

#### Scenario: Cache is restored and downgraded
- **WHEN** the application starts with a valid cached snapshot
- **THEN** the snapshot is displayed as stale and any healthy health becomes partial until the next successful refresh

#### Scenario: Cache is corrupt
- **WHEN** the cache file cannot be parsed
- **THEN** the application falls back to the `.bak` copy or starts empty without failing to launch

#### Scenario: Invalid snapshot is not persisted
- **WHEN** a snapshot fails validation
- **THEN** it is not written to the cache

### Requirement: Provider configuration and per-kind defaults
The Flutter application SHALL expose the same provider fields (`id`, `name`, `kind`, `enabled`, `executable`, `baseUrl`, `encryptedApiKey`, `encryptedCloudKey`, `usagePath`, `balancePath`, `jsonPointers`, `budget`, `allowLoopbackHttp`) and SHALL apply the same per-kind defaults: DeepSeek `https://api.deepseek.com` with `/user/balance`; Ollama `http://localhost:11434` with loopback HTTP enabled; empty defaults for Codex, Claude and OpenAI-compatible.

#### Scenario: Ollama provider is added
- **WHEN** the user adds an Ollama provider
- **THEN** it defaults to `http://localhost:11434`, loopback HTTP enabled, and remains disabled

#### Scenario: Existing configuration is preserved
- **WHEN** a configuration without a given provider kind is loaded
- **THEN** startup does not silently add or enable providers

#### Scenario: Legacy executable references are normalized
- **WHEN** a Codex or Claude provider stores an absolute path that is equivalent to the discovered executable
- **THEN** it is rewritten to the portable command name as the reference does, when the reference would do so

### Requirement: Configuration validation
The Flutter application SHALL reject invalid configuration with the same rules as the reference: schema version must be 1; refresh interval 1–60; overlay opacity 50–100; overlay margin 0–96; non-empty provider id and name; Ollama base URL required; budget must be a non-negative decimal; cloud credentials only for Ollama; routes bounded, same-origin and beginning with `/`; at most 16 JSON Pointer mappings, each a valid pointer starting with `/`.

#### Scenario: Invalid interval
- **WHEN** the refresh interval is outside 1–60
- **THEN** saving is rejected with an interval error and the previous configuration is kept

#### Scenario: Cloud credential on a non-Ollama provider
- **WHEN** a provider other than Ollama carries a cloud credential
- **THEN** saving is rejected and the credential is not persisted

#### Scenario: Provider field validation before saving
- **WHEN** an enabled Codex or Claude provider has no executable, a URL-based provider has no base URL, or a mapping does not start with `/`
- **THEN** saving is rejected with the same message the reference presents

### Requirement: Atomic persistence and backup recovery
The Flutter application SHALL write settings and cache atomically through a temporary file and rotate the previous file to `.bak`, and SHALL recover from `.bak` when the primary file is unreadable, reporting recovery as the reference does.

#### Scenario: Write is interrupted
- **WHEN** a write does not complete
- **THEN** the previous valid file remains available as `.bak` and is used on the next load

#### Scenario: Primary file is corrupt
- **WHEN** the primary settings file cannot be parsed and a valid backup exists
- **THEN** the backup is loaded and recovery is reported

### Requirement: Platform data locations
The Flutter application SHALL resolve data locations with the same precedence as the reference: `AI_USAGE_DATA_DIR` override first; then a writable `data/` directory next to the executable as portable; then a per-user directory (`%LOCALAPPDATA%\AIUsageMonitor` on Windows, `$XDG_DATA_HOME/ai-usage-monitor` or `$HOME/.local/share/ai-usage-monitor` on Linux), and SHALL report whether the location is portable.

#### Scenario: Portable directory is writable
- **WHEN** the executable directory allows writing
- **THEN** data is stored under `data/` next to the executable and reported as portable

#### Scenario: Portable directory is not writable
- **WHEN** the executable directory is read-only
- **THEN** data is stored in the per-user location and reported as a user profile

#### Scenario: Environment override
- **WHEN** `AI_USAGE_DATA_DIR` is set
- **THEN** that directory is used and reported as non-portable

### Requirement: Credential protection and redaction
The Flutter application SHALL persist credentials only as opaque protected tokens through an OS-backed store: DPAPI on Windows and Secret Service on Linux, with a session-only fallback when persistent storage is unavailable. Credential material MUST NOT appear in plaintext in settings, cache, diagnostics, provider errors or logs, and diagnostics SHALL redact it as the reference does.

#### Scenario: Persistent storage is available
- **WHEN** the user saves a credential with persistence enabled
- **THEN** an opaque token is stored and the plaintext is not written to disk

#### Scenario: Persistent storage is unavailable
- **WHEN** no OS secret service is available on Linux
- **THEN** the credential is kept only for the session, the availability notice is shown, and the user is not blocked

#### Scenario: Secret appears in a diagnostic message
- **WHEN** a connection-test or error message would contain credential material
- **THEN** the application replaces it with the redaction marker before displaying it

### Requirement: Endpoint URL safety
The Flutter application SHALL accept `https` endpoints always and `http` endpoints only for `localhost`, `127.0.0.1`, `[::1]` or `::1` when loopback HTTP is explicitly enabled for that provider, SHALL send no redirects, SHALL cap responses at 1 MiB with a 10-second default timeout, and SHALL reject unsafe URLs for every request.

#### Scenario: Loopback HTTP is allowed
- **WHEN** the provider points to `http://localhost` with loopback HTTP enabled
- **THEN** requests are permitted

#### Scenario: Remote HTTP is rejected
- **WHEN** a provider points to an `http://` URL on a non-loopback host without an exception
- **THEN** saving and testing are rejected with an HTTPS requirement and no request is sent

#### Scenario: Redirect or oversized response
- **WHEN** an endpoint returns a redirect or a body larger than 1 MiB
- **THEN** the request fails with the reference error and no truncated data is accepted
