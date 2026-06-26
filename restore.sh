#!/bin/bash
set -e

ASAR="/Applications/OpenCode.app/Contents/Resources/app.asar"
BACKUP="$ASAR.bak"

if [ ! -f "$BACKUP" ]; then
  echo "No backup found at $BACKUP"
  exit 1
fi

cp "$BACKUP" "$ASAR"
codesign --force --deep --sign - "/Applications/OpenCode.app"
echo "✓ Restored. Restart OpenCode."
