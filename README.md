# opencode-summary-patch

Fixes the `Tool call not allowed while generating summary: bash` crash in OpenCode desktop (macOS), without modifying the source code.

**Upstream issue:** [anomalyco/opencode#23709](https://github.com/anomalyco/opencode/issues/23709)

## What it does

During context compaction, OpenCode throws an error when the model emits any tool call while generating the session summary. This causes the session to reset. The patch replaces those `throw` statements with a silent `return`, matching the fix proposed in [PR #23737](https://github.com/anomalyco/opencode/pull/23737).

## Requirements

- macOS
- Node.js
- OpenCode installed via `brew install --cask opencode-desktop`

## Usage

```bash
chmod +x patch.sh && ./patch.sh
```

The original `app.asar` is backed up as `app.asar.bak` before any changes.

## Restore original

```bash
chmod +x restore.sh && ./restore.sh
```

## Note

After each OpenCode update via Homebrew, re-run `patch.sh` — the update overwrites the app bundle.
