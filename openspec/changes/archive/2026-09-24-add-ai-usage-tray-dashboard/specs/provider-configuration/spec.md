## ADDED Requirements

### Requirement: Visual provider management
The system MUST provide a visual settings window where users can enable, disable, add, edit and remove Claude, Codex, DeepSeek and generic OpenAI-compatible provider entries without editing files or using a terminal.

#### Scenario: First launch with installed clients
- **WHEN** the settings file does not exist and Codex or Claude is discoverable on the host
- **THEN** the application creates disabled or reviewable detected entries and presents their executable paths for confirmation without starting an authentication flow

#### Scenario: Disabled provider
- **WHEN** a user disables a provider and saves settings
- **THEN** automatic refresh stops for that provider while its configuration remains available for later re-enabling

### Requirement: Provider-specific fields
The settings UI MUST expose only fields relevant to the selected provider, including executable path for local clients, base URL and API key for HTTP providers, DeepSeek preset, optional usage or balance route mappings, and optional budget used for derived values.

#### Scenario: Select DeepSeek preset
- **WHEN** the user selects DeepSeek
- **THEN** the documented base URL and balance mapping are populated while the API key remains required and editable

#### Scenario: Configure generic compatible endpoint
- **WHEN** the user selects OpenAI-compatible
- **THEN** the UI permits base URL, credential, health test and optional explicit metric routes without assuming a DeepSeek schema

### Requirement: Secure credential persistence
The system MUST never write provider secrets in plaintext to settings, cache or logs. On Windows it MUST protect stored secrets with current-user DPAPI; on Linux it MUST use Secret Service or keep the secret session-only when secure storage is unavailable.

#### Scenario: Save API key on Windows
- **WHEN** a user saves a valid API key with persistence enabled
- **THEN** the settings file contains only an opaque DPAPI-protected value that another Windows user cannot decrypt

#### Scenario: Portable folder is copied
- **WHEN** settings protected for one user or machine are opened where they cannot be decrypted
- **THEN** the provider is marked as requiring credentials and the application does not expose or discard the encrypted bytes silently

#### Scenario: Linux secret service unavailable
- **WHEN** secure storage cannot be reached on Linux
- **THEN** the UI explains that the key can be session-only and does not offer plaintext persistence

### Requirement: Connection testing before save
The configuration window MUST offer a non-destructive connection test that validates executable/protocol compatibility or HTTP authentication and schema mappings, with secret-redacted diagnostics.

#### Scenario: Test Codex executable
- **WHEN** the configured Codex path can start app-server and complete initialization
- **THEN** the test reports compatible version and account availability without modifying Codex authentication

#### Scenario: HTTP credentials rejected
- **WHEN** a provider returns an authentication failure during testing
- **THEN** the test identifies authentication as the problem without displaying the key or authorization header

### Requirement: Refresh and network settings
The settings UI MUST provide a refresh interval from 1 to 60 minutes, defaulting to 5, and MUST provide timeout and local-HTTP controls only within safe supported bounds.

#### Scenario: Invalid refresh interval
- **WHEN** the user enters a value outside 1 through 60 minutes
- **THEN** saving is blocked with an inline validation message

#### Scenario: Non-loopback HTTP endpoint
- **WHEN** the user configures an unencrypted non-loopback URL
- **THEN** saving or connection testing is rejected

### Requirement: Versioned and atomic settings
The system MUST store non-secret configuration in a versioned JSON document, validate it before use, write changes atomically and recover from the last valid backup when the current document is truncated or invalid.

#### Scenario: Interrupted settings write
- **WHEN** the process stops before an atomic replacement completes
- **THEN** the next launch loads the prior valid configuration and reports recovery rather than resetting all providers

### Requirement: Portable data location visibility
The system MUST store data beside the executable when that location is writable, otherwise use the per-user application data directory, and MUST show and open the active data location from settings.

#### Scenario: Read-only executable folder
- **WHEN** the application cannot safely create its data directory beside the executable
- **THEN** it uses the per-user location and identifies that fallback in settings
