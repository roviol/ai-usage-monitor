## Purpose

Define safe, fail-closed monitoring of a local or self-hosted Ollama server by observing its loaded-model status without triggering inference or inventing usage quotas.

## ADDED Requirements

### Requirement: Selectable and persistent Ollama provider
The application SHALL expose Ollama as a new provider type that users can add, edit, enable, disable, test, and remove. A newly added Ollama provider SHALL default to disabled, use `http://localhost:11434`, and permit explicit HTTP for loopback endpoints. The provider configuration and normalized snapshots SHALL use the provider identifier `ollama`; loading settings or cache written before this capability MUST continue to work.

#### Scenario: User adds an Ollama provider
- **WHEN** the user selects the Ollama provider type and adds it
- **THEN** the editor presents a configurable Ollama base URL and an optional credential, pre-fills `http://localhost:11434`, and leaves the provider disabled

#### Scenario: Settings are saved and restored
- **WHEN** an Ollama provider with its URL, credential, loopback HTTP preference and enabled state is saved
- **THEN** loading the configuration restores those choices while preserving unrelated providers and preferences

#### Scenario: Legacy settings are loaded
- **WHEN** an existing configuration contains no Ollama provider
- **THEN** startup preserves the existing provider list and does not silently add or enable Ollama

### Requirement: Loaded-model status from Ollama
For an enabled Ollama provider, the application SHALL obtain status by sending only a bounded `GET` request to `/api/ps` and SHALL display whether the service is reachable, the number of currently loaded models, each model name, and the bytes of memory/VRAM reported for each model. When the response contains a future unload time for a model, the application SHALL display that time as model unload information rather than quota-reset information.

#### Scenario: One model is loaded
- **WHEN** `/api/ps` returns one running model with a non-negative memory/VRAM size
- **THEN** the Ollama snapshot reports one loaded model, the model name, and that size in bytes without creating a percentage quota

#### Scenario: Server is healthy but idle
- **WHEN** `/api/ps` succeeds with no running models
- **THEN** the snapshot remains healthy and reports zero loaded models rather than treating the empty result as an error

#### Scenario: Unload time is published
- **WHEN** a loaded model includes a future unload time
- **THEN** the corresponding row identifies the time as model unload time, not quota reset time

### Requirement: Honest coverage without inference
The Ollama provider SHALL report token usage, quota, remaining quota, spend and balance as unsupported. It MUST NOT call generation or completion endpoints, read Ollama's private files, or send any prompt to a model.

#### Scenario: Usage is reviewed
- **WHEN** the user views an Ollama provider card
- **THEN** only connection and loaded-model observations are shown and the interface clearly distinguishes them from token/cost usage

#### Scenario: Schema exposes extra or missing fields
- **WHEN** `/api/ps` omits optional fields or returns an unrecognized schema
- **THEN** the adapter does not synthesize usage values and reports only the fields it can validate

### Requirement: Secure transport and credentials
The Ollama endpoint MUST satisfy the application's URL safety policy. HTTP SHALL be accepted only for loopback addresses when explicitly allowed for that provider; non-loopback instances MUST use HTTPS. If the user supplies a credential, it SHALL be stored through the platform secret store and sent as a Bearer credential; otherwise no Authorization header SHALL be sent. Credential material MUST NOT appear in settings diagnostics, cache files, provider errors or connection-test messages.

#### Scenario: Loopback HTTP is used
- **WHEN** the provider points to `http://localhost:11434` with loopback HTTP enabled
- **THEN** the request is allowed

#### Scenario: Remote HTTP is rejected
- **WHEN** the user enters an `http://` URL on a non-loopback host without an explicit loopback exception
- **THEN** saving and testing are rejected with an HTTPS requirement

#### Scenario: Optional credential is used
- **WHEN** the user has stored a Bearer credential
- **THEN** `/api/ps` requests carry the credential and diagnostics redact it

### Requirement: Fail-closed error handling and persistence
A non-success response, timeout, malformed JSON, or invalid model entry SHALL be treated as a provider error and preserve the last valid cached snapshot as stale. A successful valid response SHALL be cached atomically and restored as stale on application startup until the next successful refresh.

#### Scenario: Ollama is unreachable
- **WHEN** the refresh cannot reach `/api/ps`
- **THEN** the provider reports a transient error, the last valid metrics remain marked stale, and no model data is invented

#### Scenario: Response is unauthorized
- **WHEN** `/api/ps` returns 401 or 403
- **THEN** the provider reports an authentication error without exposing the configured credential

#### Scenario: Restart occurs before refresh
- **WHEN** the application restarts with a cached valid Ollama snapshot
- **THEN** it shows that snapshot as stale until a refresh completes
