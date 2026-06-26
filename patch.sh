#!/bin/bash
set -e

APP="/Applications/OpenCode.app"
ASAR="$APP/Contents/Resources/app.asar"
PLIST="$APP/Contents/Info.plist"
CHUNK="out/main/chunks/node-C8DkvgUn.js"
TMP=$(mktemp -d)

trap 'rm -rf "$TMP"' EXIT

# Preserve original backup — don't overwrite if it already exists
if [ ! -f "$ASAR.bak" ]; then
  cp "$ASAR" "$ASAR.bak"
  echo "→ Backup created: app.asar.bak"
fi

echo "→ Extracting app.asar..."
npx --yes @electron/asar extract "$ASAR" "$TMP"

echo "→ Patching..."
CHUNK_PATH="$TMP/$CHUNK" node - <<'JS'
const fs = require('fs');
const file = process.env.CHUNK_PATH;
let code = fs.readFileSync(file, 'utf8');
let count = 0;

function patch(from, to) {
  if (code.includes(to)) { console.log('already patched:', to.slice(0, 60)); return; }
  if (!code.includes(from)) { console.warn('WARN not found:', from.slice(0, 60)); return; }
  code = code.replace(from, to);
  count++;
  console.log('patched:', from.slice(0, 60));
}

// Guard 1: tool-input-start (may already be patched)
patch(
  'case "tool-input-start":\n            if (ctx.assistantMessage.summary) {\n              throw new Error(`Tool call not allowed while generating summary: ${value4.name}`);\n            }\n            yield* ensureToolCall(value4);',
  'case "tool-input-start":\n            if (ctx.assistantMessage.summary) {\n              return;\n            }\n            yield* ensureToolCall(value4);'
);

// Guard 2: tool-input-delta — missing guard, ensureToolCall creates corrupted DB entries
patch(
  'case "tool-input-delta":\n            {\n              const toolCall3 = yield* ensureToolCall(value4);',
  'case "tool-input-delta":\n            {\n              if (ctx.assistantMessage.summary) return;\n              const toolCall3 = yield* ensureToolCall(value4);'
);

// Guard 3: tool-input-end — same issue
patch(
  'case "tool-input-end": {\n            const toolCall3 = yield* ensureToolCall(value4);',
  'case "tool-input-end": {\n              if (ctx.assistantMessage.summary) return;\n              const toolCall3 = yield* ensureToolCall(value4);'
);

// Guard 4: tool-call (may already be patched)
patch(
  'case "tool-call": {\n            if (ctx.assistantMessage.summary) {\n              throw new Error(`Tool call not allowed while generating summary: ${value4.name}`);\n            }',
  'case "tool-call": {\n            if (ctx.assistantMessage.summary) {\n              return;\n            }'
);

fs.writeFileSync(file, code);
console.log('total new patches:', count);
JS

echo "→ Repacking..."
npx @electron/asar pack "$TMP" "$ASAR"

echo "→ Updating integrity hash in Info.plist..."
NEW_HASH=$(shasum -a 256 "$ASAR" | cut -d' ' -f1)
/usr/libexec/PlistBuddy -c "Set :ElectronAsarIntegrity:Resources/app.asar:hash $NEW_HASH" "$PLIST"

echo "→ Re-signing with ad-hoc signature..."
codesign --force --deep --sign - "$APP"

echo "✓ Done. Restart OpenCode."
