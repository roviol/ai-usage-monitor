# Parity verification

## Corpus

`test/parity/reference/` holds expected outputs generated from the C++
reference application by `scripts/parity-dump-reference.sh` (run from the
repository root). Regenerate with:

```bash
./scripts/parity-dump-reference.sh flutter_app/test/parity/reference
```

Files: `settings_default.json`, `settings_populated.json`,
`settings_redacted.json`, `redacted_export.json`, `cache_snapshots.json`,
`tooltip.txt`, `overlay_projection.txt`, `decimal_cases.txt`.

The Dart tests in `test/parity/parity_test.dart` compare the Flutter codec,
tooltip and overlay projection against these outputs byte-for-byte (modulo
the corpus' trailing newline).

## Manual side-by-side comparison

1. Build both applications.
   - C++: `cmake --preset release && cmake --build --preset release` (see README).
   - Flutter: `cd flutter_app && flutter build linux --release`.
2. Create one shared data directory: `mkdir -p /tmp/aiu-shared` and write a
   `settings.json` there (or copy one from either app's data directory).
3. Launch both against it:
   ```bash
   AI_USAGE_DATA_DIR=/tmp/ai-usage-data /path/to/cpp-app &
   AI_USAGE_DATA_DIR=/tmp/ai-usage-data ./flutter_app/build/linux/x64/release/bundle/ai_usage_monitor &
   ```
   Run only one app at a time when editing configuration (last writer wins;
   both rotate `.bak`).
4. Compare after each refresh: provider list, card contents, tray icon color
   and tooltip, overlay rows and countdowns. The Flutter single-instance
   signal uses a Flutter-specific name so both binaries run concurrently.
5. For automated checks, `cd flutter_app && flutter test test/parity` runs
   the corpus comparison.

Note: `AI_USAGE_UI_FIXTURES=1` puts the C++ app in fixture mode for
screenshot comparisons; both apps expose the same normalized snapshots for
the same inputs.