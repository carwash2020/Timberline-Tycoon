#!/usr/bin/env bash
# One-time setup on a new Mac (or Linux) computer. From the repo folder:
#   ./setup.sh
# 1. Installs Rokit (the toolchain manager) if it's missing.
# 2. Installs the exact tool versions pinned in rokit.toml
#    (Rojo, StyLua, Selene, luau-lsp).
# 3. Installs the matching Rojo plugin into Roblox Studio.
# Safe to re-run: anything already installed is left alone.
set -euo pipefail
cd "$(dirname "$0")"

ROKIT_BIN="$HOME/.rokit/bin"

if ! command -v rokit >/dev/null 2>&1 && [ ! -x "$ROKIT_BIN/rokit" ]; then
	echo "==> Installing Rokit"
	curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
fi
# The installer adds Rokit to PATH for *new* terminals; make it work in this one too.
export PATH="$ROKIT_BIN:$PATH"

echo "==> Trusting the tools listed in rokit.toml"
for tool in $(sed -n 's/^[A-Za-z0-9_-]* *= *"\([^@"]*\)@.*"/\1/p' rokit.toml); do
	rokit trust "$tool"
done

echo "==> Installing tools"
if ! rokit install; then
	echo
	echo "Couldn't download the tools. Check the internet connection and run 'bash setup.sh' again."
	echo "On a shared network GitHub may be rate-limiting you: run 'rokit authenticate github' first."
	exit 1
fi

echo "==> Installing the Rojo plugin into Roblox Studio"
if ! rojo plugin install; then
	echo "Couldn't install the Studio plugin automatically. Install Roblox Studio (and open it"
	echo "once), then run 'bash setup.sh' again, or add 'Rojo' from Studio's Plugins marketplace."
fi

echo
echo "All set. Open a new terminal, then:"
echo "  rojo serve      (leave it running)"
echo "  In Roblox Studio: Plugins -> Rojo -> Connect, then press Play."
