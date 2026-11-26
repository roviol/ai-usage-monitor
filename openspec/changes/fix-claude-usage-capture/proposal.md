## Why

Claude Code 2.1.317 returns a successful, cost-only `/usage` response when no account is logged in. The monitor misreports this as an unsupported output schema, hiding the action needed to restore subscription capture.

## What Changes

- Check authentication through the public `claude auth status --json` command without reading credentials.
- Distinguish missing login, API billing, authentication probe failure, and genuine quota output incompatibility.
- Keep the existing local non-interactive quota capture, stale data behavior, and a shared ten-second refresh deadline.
- Add regression coverage, install the fix, and prepare version 0.4.2 artifacts and release notes for review before commit/push.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `provider-usage-monitoring`: Claude authentication diagnostics and bounded local command execution.

## Impact

Claude provider, process fixtures/tests, privacy/troubleshooting documentation, and release metadata. No new dependency or direct Anthropic API call. Real subscription validation requires the user to authenticate the installed client.
