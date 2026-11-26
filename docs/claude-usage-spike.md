# Claude Code usage spike

Date: 2026-08-05. Tested client: Claude Code 2.1.221 on Windows x64.

Only non-consuming commands were executed:

- `claude --version`
- `claude --help`
- `claude auth status --json`
- `claude /usage` with redirected standard output

With stdout redirected, `claude /usage` exits normally and prints the current
session and weekly percentages as plain text. It does not require `--print`, a
prompt, stdin, a PTY/ConPTY session, or a direct Anthropic API credential.

Conclusion: the subscription adapter executes exactly the local command
`claude /usage`, parses only recognized percentage lines, and fails closed when
the output changes. The Admin Usage & Cost API adapter and interactive terminal
bridge are intentionally out of scope. The fixture in
`tests/fixtures/claude_usage_screen.txt` contains no account or credential data.

## Follow-up: 2026-11-24, Linux, Claude Code 2.1.317

`claude auth status --json` reports `loggedIn: false`, `authMethod: none`, and `apiProvider: firstParty`. In that state, both `claude /usage` and `claude -p /usage` exit zero and print cost/duration/token totals without subscription percentages. A PTY with safe mode also shows only session totals; it is not a solution for absent authentication. No model request was made.

The last stored successful subscription snapshot is dated 2026-11-23 13:27:05 UTC. The observed failure establishes missing local authentication, not a proven output regression for authenticated accounts. Version 0.4.2 probes the public auth command first, returns an actionable unauthorized error, and preserves the old quota parser and stale values. Older clients without auth status retain the original capture path. Real subscription recovery must be checked after the user completes `claude auth login --claudeai`.

After the user renewed the expired login, the public auth command reported `loggedIn: true`, `authMethod: claude.ai`, and a subscription account. The real provider probe succeeded (`usage-compatible=yes metrics=4`), confirming that the existing parser still captures session and weekly used/remaining percentages. The incident was an expired login, not an observed quota format incompatibility.
