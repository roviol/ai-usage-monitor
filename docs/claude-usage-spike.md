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
