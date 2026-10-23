#!/usr/bin/env bash
# Runs every check that doesn't need Roblox Studio:
#   formatting (StyLua), lint (Selene), strict type-checking against the
#   real Roblox API (luau-lsp), the unit tests (Lune), and whether ECONOMY.md
#   matches the balance tables, and meshlint (the GLBs have nothing solid in a
#   log lane or a doorway: tools/blender/meshlint.py). Run from the repo root: ./scripts/check.sh
# Tools come from rokit.toml (`rokit install`). GitHub runs this on every
# push to main and every pull request (.github/workflows/checks.yml).
#
#   ./scripts/check.sh               everything (the default)
#   ./scripts/check.sh --lint-only   everything except the unit tests
#   ./scripts/check.sh --tests-only  only the unit tests
# Set TEST_SHARD=2/4 to run one shard of the tests (see tests/run.luau).
set -euo pipefail
cd "$(dirname "$0")/.."

RUN_LINT=1
RUN_TESTS=1
case "${1:-}" in
"") ;;
--lint-only) RUN_TESTS=0 ;;
--tests-only) RUN_LINT=0 ;;
*)
	echo "Usage: ./scripts/check.sh [--lint-only | --tests-only]" >&2
	exit 2
	;;
esac

if [ "$RUN_LINT" = 1 ]; then
	# The Roblox type definitions are pinned (scripts/globalTypes.pin: the
	# luau-lsp tag, kept equal to the luau-lsp version in rokit.toml) and
	# cached in the repo root (gitignored; CI caches it keyed on the pin). A
	# cache from another pin is replaced, so changing the pin refreshes it.
	DEFS=globalTypes.d.luau
	PIN=$(tr -d '[:space:]' <scripts/globalTypes.pin)
	if [ ! -s "$DEFS" ] || [ "$(cat "$DEFS.pin" 2>/dev/null)" != "$PIN" ]; then
		echo "Downloading Roblox type definitions (luau-lsp $PIN)..."
		curl -fsSL -o "$DEFS.tmp" "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/$PIN/scripts/globalTypes.d.luau"
		mv "$DEFS.tmp" "$DEFS"
		printf '%s' "$PIN" >"$DEFS.pin"
	fi

	echo "== StyLua (formatting)"
	stylua --check src tools tests

	echo "== Selene (lint)"
	selene src

	echo "== luau-lsp (types vs. Roblox API)"
	rojo sourcemap default.project.json -o sourcemap.json
	luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json \
		--definitions=@roblox="$DEFS" --ignore="**/Vendor/**" src
fi

if [ "$RUN_TESTS" = 1 ]; then
	echo "== Tests${TEST_SHARD:+ (shard $TEST_SHARD)}"
	lune run tests/run
fi

if [ "$RUN_LINT" = 1 ]; then
	echo "== ECONOMY.md is current"
	lune run tools/economy --check
	lune run tools/economy1 --check
	echo "== ASSETS.md is current"
	lune run tools/assets --check
	echo "== meshlint (no solid in a lane or door of a mesh)"
	python3 tools/blender/meshlint.py
	python3 tools/blender/test_meshlint.py
fi

echo "All checks passed."
