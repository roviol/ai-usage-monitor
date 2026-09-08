# Ollama Local Monitoring Specification

## Purpose

Define safe, fail-closed monitoring of a local or self-hosted Ollama server by observing its loaded-model status without triggering inference or inventing usage quotas.

## Requirements

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
For an enabled Ollama provider, the application SHALL obtain loaded-model status by sending a bounded `GET` request to `/api/ps` and SHALL display whether the service is reachable, the number of currently loaded models, each model name, and the bytes of memory/VRAM reported for each model. When the response contains a future unload time for a model, the application SHALL display that time as model unload information rather than quota-reset information.

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
The Ollama provider SHALL report token counts, spend and balance as unsupported: no Ollama endpoint publishes them per account. It MUST NOT call generation or completion endpoints, read Ollama's private files, or send any prompt to a model. Every figure it shows MUST be one the provider reported or a percentage computed from one; the application MUST NOT read a published price list or infer usage from observed model activity.

#### Scenario: Usage is reviewed
- **WHEN** the user views an Ollama provider card
- **THEN** connection, loaded-model and, when configured, monthly credit observations are shown, each identified by what reported it

#### Scenario: Schema exposes extra or missing fields
- **WHEN** `/api/ps` omits optional fields or returns an unrecognized schema
- **THEN** the adapter does not synthesize usage values and reports only the fields it can validate

### Requirement: Account plan without invented credits
For an enabled Ollama provider, the application MAY additionally send one bounded, read-only `POST` request to `/api/me` in order to label the snapshot with the signed-in account name and its plan. That request SHALL be supplementary: a failure, a non-success status, or an unrecognized schema MUST leave the loaded-model observation healthy and simply produce no account label. The account label SHALL carry only the account name and plan; the response's e-mail address and identifiers MUST NOT be persisted.

#### Scenario: Signed-in account is labeled
- **WHEN** `/api/me` returns a valid account with a plan
- **THEN** the provider shows that account name and plan next to the loaded-model observation

#### Scenario: Server has no signed-in account
- **WHEN** `/api/me` fails, is unavailable, or returns an unrecognized schema
- **THEN** the snapshot keeps its loaded-model data, remains healthy, and shows no account label

#### Scenario: Credit figures are sought
- **WHEN** the user looks for the monthly credit allowance or the credits already consumed
- **THEN** the interface reports them as unsupported and derives no figure from the plan name

### Requirement: Monthly credit consumption from Ollama Cloud
When, and only when, the user has stored an ollama.com API key for the provider, the application SHALL send a bounded `GET` request to `https://ollama.com/api/usage` and display the consumed share of the monthly allowance together with the per-model request counts that endpoint reports. That endpoint reports consumption as a `0..1` fraction and publishes no currency amount, so the application SHALL present it as a used and remaining percentage, in the same shape as every other provider's quota, and SHALL NOT produce any currency figure.

The cloud credential SHALL be stored through the platform secret store, SHALL be sent only to `ollama.com`, and MUST NOT be sent to the configured base URL. Conversely the credential held for the configured server MUST NOT be sent to `ollama.com`. A provider that is not an Ollama provider MUST NOT retain a cloud credential.

#### Scenario: Credits are reported
- **WHEN** `/api/usage` returns a monthly usage fraction and per-model request counts
- **THEN** the provider shows the consumed percentage, the remaining percentage and each model's request count

#### Scenario: No currency amount is produced
- **WHEN** `/api/usage` reports a fraction
- **THEN** only percentages and request counts are shown, and no spend, balance or allowance figure is derived from it

#### Scenario: No cloud credential is stored
- **WHEN** the provider has no ollama.com API key
- **THEN** no request is sent to `ollama.com`, credits are reported as unsupported, and the loaded-model observation is unaffected

#### Scenario: Credit lookup fails
- **WHEN** `/api/usage` is unreachable, rejects the credential, or returns a usage value outside `0..1`
- **THEN** the provider degrades to partial, keeps the loaded-model observation, invents no credit figure, and reports the failure without exposing the credential

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
