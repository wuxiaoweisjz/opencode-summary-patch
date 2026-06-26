#!/bin/bash
set -e

APP="/Applications/OpenCode.app"
ASAR="$APP/Contents/Resources/app.asar"
PLIST="$APP/Contents/Info.plist"
CHUNK="out/main/chunks/node-C8DkvgUn.js"
TMP=$(mktemp -d)

trap 'rm -rf "$TMP"' EXIT

echo "→ Extracting app.asar..."
npx --yes @electron/asar extract "$ASAR" "$TMP"

echo "→ Patching..."
CHUNK_PATH="$TMP/$CHUNK" node - <<'JS'
const fs = require('fs');
const file = process.env.CHUNK_PATH;
let code = fs.readFileSync(file, 'utf8');
const target = 'throw new Error(`Tool call not allowed while generating summary: ${value4.name}`);';
const n = code.split(target).length - 1;
if (!n) { console.error('No match – already patched or wrong version?'); process.exit(1); }
fs.writeFileSync(file, code.replaceAll(target, 'return; // skip tool call during summary'));
console.log('Patched ' + n + ' occurrence(s)');
JS

echo "→ Repacking (original backed up to app.asar.bak)..."
cp "$ASAR" "$ASAR.bak"
npx @electron/asar pack "$TMP" "$ASAR"

echo "→ Updating integrity hash in Info.plist..."
NEW_HASH=$(shasum -a 256 "$ASAR" | cut -d' ' -f1)
/usr/libexec/PlistBuddy -c "Set :ElectronAsarIntegrity:Resources/app.asar:hash $NEW_HASH" "$PLIST"

echo "→ Re-signing with ad-hoc signature..."
codesign --force --deep --sign - "$APP"

echo "✓ Done. Restart OpenCode."
