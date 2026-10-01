#!/usr/bin/env bash
# Screenshots of a preview scene, no browser window needed:
#   bash tools/preview/shoot.sh <scene> [view] [WIDTHxHEIGHT]
#   bash tools/preview/shoot.sh town 3        just view 3 of the town
#   bash tools/preview/shoot.sh trees         every view of the trees
# Writes preview/<scene>-<view>.png (gitignored). Re-exports
# preview/<scene>.html first when it's missing or older than the code it
# comes from (.luau under src/ and tools/preview/, tools/loader.luau and
# tools/preview/viewer.html).
# Heavy scenes (world, terrain) take up to ~3 minutes a view on 4 cores:
# shoot one view at a time, and one scene at a time.
#
# Needs Node and Playwright with a Chromium (both come preinstalled in
# Claude Code cloud sessions; elsewhere `npx playwright install chromium`).
# three.js and Playwright are linked once into $RENDER_HOME
# (default ~/.cache/timberline-render), so renders work offline.
set -euo pipefail
cd "$(dirname "$0")/../.."

SCENE=${1:?usage: bash tools/preview/shoot.sh <scene> [view] [WIDTHxHEIGHT]}
shift
HTML="preview/$SCENE.html"
RENDER_HOME=${RENDER_HOME:-$HOME/.cache/timberline-render}

if [ ! -f "$HTML" ] || [ -n "$(find src tools/preview tools/loader.luau -newer "$HTML" \( -name '*.luau' -o -path tools/preview/viewer.html \) -print -quit)" ]; then
	echo "== Exporting $SCENE"
	lune run tools/preview/export "$SCENE"
fi

if [ ! -d "$RENDER_HOME/node_modules/three" ] || [ ! -e "$RENDER_HOME/node_modules/playwright" ]; then
	echo "== Setting up the renderer in $RENDER_HOME"
	mkdir -p "$RENDER_HOME/node_modules"
	[ -f "$RENDER_HOME/package.json" ] || echo '{ "name": "timberline-render", "private": true }' >"$RENDER_HOME/package.json"
	[ -d "$RENDER_HOME/node_modules/three" ] || npm install --prefix "$RENDER_HOME" --no-save --silent three@0.170.0
	# Reuse a global Playwright (its browsers are already installed) when there is one.
	for pkg in playwright playwright-core; do
		found=$(node -e "try { console.log(require('path').dirname(require.resolve('$pkg/package.json'))) } catch (e) {}")
		if [ -n "$found" ] && [ ! -e "$RENDER_HOME/node_modules/$pkg" ]; then
			ln -s "$found" "$RENDER_HOME/node_modules/$pkg"
		fi
	done
	[ -e "$RENDER_HOME/node_modules/playwright" ] || npm install --prefix "$RENDER_HOME" --no-save --silent playwright
fi

# render.mjs imports Playwright, which Node resolves next to the script.
cp tools/preview/render.mjs "$RENDER_HOME/render.mjs"
THREE_DIR="$RENDER_HOME/node_modules/three" node "$RENDER_HOME/render.mjs" "$PWD/$HTML" "$@"
