## MODIFIED Requirements

### Requirement: Visual provider management
The system MUST provide a visual settings window where users can enable, disable, add, edit and remove Claude, Codex, Antigravity (`agy`), DeepSeek and generic OpenAI-compatible provider entries without editing files or using a terminal.

#### Scenario: First launch with installed clients
- **WHEN** the settings file does not exist and Codex, Claude or `agy` is discoverable on the host
- **THEN** the application creates detected entries using portable executable references and presents their executable paths for confirmation without starting an authentication flow

#### Scenario: Disabled provider
- **WHEN** a user disables a provider and saves settings
- **THEN** automatic refresh stops for that provider while its configuration remains available for later re-enabling

#### Scenario: Add or edit agy provider
- **WHEN** the user adds or selects an `agy` provider entry in settings
- **THEN** the editor shows only the local-client fields (name, type, executable path, and enabled toggle) and validates that an enabled `agy` entry has an executable configured

### Requirement: Connection testing before save
The configuration window MUST offer a non-destructive connection test that validates executable/protocol compatibility or HTTP authentication and schema mappings, with secret-redacted diagnostics.

#### Scenario: Test Codex executable
- **WHEN** the configured Codex path can start app-server and complete initialization
- **THEN** the test reports compatible version and account availability without modifying Codex authentication

#### Scenario: Test agy executable
- **WHEN** the user tests a configured `agy` executable
- **THEN** the test runs the non-interactive quota check without modifying `agy` authentication and reports either available quota compatibility or an actionable secret-free diagnostic

#### Scenario: HTTP credentials rejected
- **WHEN** a provider returns an authentication failure during testing
- **THEN** the test identifies authentication as the problem without displaying the key or authorization header
