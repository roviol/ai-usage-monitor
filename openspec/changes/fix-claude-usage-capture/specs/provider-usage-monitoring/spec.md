## MODIFIED Requirements

### Requirement: Non-interactive local Claude usage integration
The system MUST obtain Claude subscription usage exclusively by executing the installed client as `claude /usage` with redirected output, no stdin and no pseudo-terminal. It MUST NOT call the Anthropic Usage & Cost API directly or submit a model prompt solely to discover quota. It SHALL check public authentication status using `claude auth status --json` where supported, without reading private authentication files. Both local commands SHALL share the ten-second refresh deadline and cancellation handling. Diagnostics SHALL NOT include raw authentication or usage output.

#### Scenario: Recognized non-interactive Claude output
- **WHEN** the installed Claude client produces recognized session or weekly percentage lines for `claude /usage`
- **THEN** the system extracts those quota windows and each recognized next-reset time, marks their source as CLI bridge and closes the hidden child process

#### Scenario: Claude is logged out
- **WHEN** public authentication status reports `loggedIn: false`, including on a nonzero exit code
- **THEN** the refresh reports a non-transient unauthorized error instructing the user to run `claude auth login --claudeai`, and does not execute `/usage` or invent values

#### Scenario: API billing account
- **WHEN** public authentication status identifies an API-key account
- **THEN** the refresh reports subscription quotas unsupported and directs the user to subscription login

#### Scenario: Older client lacks authentication status
- **WHEN** the authentication status command fails without recognized structured status
- **THEN** the system tries the existing `/usage` capture within the remaining refresh deadline

#### Scenario: Unrecognized Claude output
- **WHEN** the redirected command output does not match a tested parser fixture
- **THEN** the system reports subscription quota as unsupported with an actionable diagnostic, retains diagnostics without secrets and does not guess values

#### Scenario: Invalid successful authentication status
- **WHEN** authentication status succeeds but does not contain a boolean login status
- **THEN** the refresh reports an authentication status format error without exposing raw output
