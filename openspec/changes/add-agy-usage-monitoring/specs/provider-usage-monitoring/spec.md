## ADDED Requirements

### Requirement: Non-interactive local Antigravity (agy) usage integration
The system MUST obtain Antigravity CLI (`agy`) quota and next-reset data exclusively by executing the installed client non-interactively in print mode (`agy -p "/usage" --output-format json`) with redirected output, closed stdin, and no pseudo-terminal. It MUST NOT read or copy private Google OAuth credential files, call Google backend APIs directly, or submit a conversational model prompt solely to discover quota. Execution SHALL respect the ten-second refresh timeout and cancellation handling, and diagnostics SHALL NOT expose raw authentication or account details.

#### Scenario: Recognized non-interactive agy quota output
- **WHEN** the installed `agy` client produces a valid structured JSON quota payload containing one or more quota buckets with used or remaining quota values and reset timestamps
- **THEN** the system normalizes each supported quota bucket into complementary used-percentage and remaining-percentage metrics with its next reset instant, marks provenance consistently with the CLI bridge, and closes the hidden child process

#### Scenario: agy authentication is unavailable
- **WHEN** `agy` reports missing or expired authentication instead of quota data
- **THEN** the refresh reports a non-transient unauthorized error instructing the user to authenticate in `agy`, without exposing tokens or inventing quota values

#### Scenario: agy session uses GEMINI_API_KEY
- **WHEN** `agy` reports that account quotas are unavailable because the session uses `GEMINI_API_KEY` (including exiting with status 2)
- **THEN** the refresh reports account quotas as unsupported with an actionable diagnostic and does not guess values

#### Scenario: Unrecognized agy output
- **WHEN** the redirected command output does not match a recognized JSON quota schema
- **THEN** the system reports quota capture as unsupported, retains diagnostics without secrets, and does not guess values
