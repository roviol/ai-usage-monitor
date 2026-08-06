#!/usr/bin/env bash
set -euo pipefail

artifact="${1:-dist/AIUsageMonitor-0.1.0-x86_64.AppImage}"
if [[ ! -f "$artifact" ]]; then
  echo "Artifact not found: $artifact" >&2
  exit 1
fi
size=$(stat -c %s "$artifact")
limit=$((45 * 1024 * 1024))
printf 'AppImage bytes: %s (limit %s)\n' "$size" "$limit"
test "$size" -le "$limit"

# Runtime RSS is measured under a virtual X server in CI. A missing tray host is
# expected there; the normal dashboard fallback remains the smoke-test surface.
tmp=$(mktemp -d)
trap 'if [[ -n "${pid:-}" ]]; then kill "$pid" 2>/dev/null || true; fi; rm -rf -- "$tmp"' EXIT
printf '%s\n' '{"schemaVersion":1,"refreshMinutes":5,"alwaysOnTop":false,"providers":[]}' > "$tmp/settings.json"
AI_USAGE_DATA_DIR="$tmp" "$artifact" >/dev/null 2>&1 &
pid=$!
sleep 60
kill -0 "$pid"
rss_kib=$(ps -o rss= -p "$pid" | tr -d ' ')
printf 'Idle RSS KiB: %s (limit 51200)\n' "$rss_kib"
test "$rss_kib" -le 51200
