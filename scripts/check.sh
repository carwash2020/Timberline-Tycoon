#!/usr/bin/env bash
# Runs every check that doesn't need Roblox Studio:
#   formatting (StyLua), lint (Selene), and strict type-checking against the
#   real Roblox API (luau-lsp). Run from the repo root: ./scripts/check.sh
# Tools come from rokit.toml (`rokit install`).
set -euo pipefail
cd "$(dirname "$0")/.."

DEFS=globalTypes.d.luau
if [ ! -f "$DEFS" ]; then
	echo "Downloading Roblox type definitions..."
	curl -fsSL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi

echo "== StyLua (formatting)"
stylua --check src

echo "== Selene (lint)"
selene src

echo "== luau-lsp (types vs. Roblox API)"
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json \
	--definitions=@roblox="$DEFS" --ignore="**/Vendor/**" src

echo "All checks passed."
