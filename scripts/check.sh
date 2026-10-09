#!/usr/bin/env bash
# Runs every check that doesn't need Roblox Studio:
#   formatting (StyLua), lint (Selene), strict type-checking against the
#   real Roblox API (luau-lsp), the unit tests (Lune), and whether ECONOMY.md
#   matches the balance tables. Run from the repo root: ./scripts/check.sh
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
	DEFS=globalTypes.d.luau
	if [ ! -f "$DEFS" ]; then
		echo "Downloading Roblox type definitions..."
		curl -fsSL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
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
fi

echo "All checks passed."
