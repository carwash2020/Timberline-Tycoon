#!/usr/bin/env bash
# The pinned toolchain (rokit.toml) on a Linux x86_64 machine without Rokit,
# e.g. a Claude Code cloud session. On a Mac use ./setup.sh instead.
#   bash scripts/cloud-setup.sh
# Downloads the release binaries into ~/.local/tools and links them into
# /usr/local/bin (or ~/.local/bin when that isn't writable). Safe to re-run.
#
# Selene downloads its Roblox standard library on first run (cached in
# ~/.cache/selene/roblox.yml). Behind a proxy with its own CA the release
# binary can't, so when that fails and Cargo is available, Selene is rebuilt
# from source with the system certificates (a few minutes, once).
set -euo pipefail
cd "$(dirname "$0")/.."

TOOLS="$HOME/.local/tools"
BIN=/usr/local/bin
[ -w "$BIN" ] || BIN="$HOME/.local/bin"
mkdir -p "$TOOLS" "$BIN"

get() { # get <name> <url>
	if [ -x "$TOOLS/$1" ]; then
		return
	fi
	echo "==> $1"
	curl -fsSL -o "$TOOLS/$1.zip" "$2"
	unzip -o -q "$TOOLS/$1.zip" -d "$TOOLS"
	rm "$TOOLS/$1.zip"
	chmod +x "$TOOLS/$1"
}

get rojo https://github.com/rojo-rbx/rojo/releases/download/v7.7.0/rojo-7.7.0-linux-x86_64.zip
get stylua https://github.com/JohnnyMorganz/StyLua/releases/download/v2.5.2/stylua-linux-x86_64.zip
get selene https://github.com/Kampfkarren/selene/releases/download/0.31.0/selene-0.31.0-linux.zip
get luau-lsp https://github.com/JohnnyMorganz/luau-lsp/releases/download/1.70.1/luau-lsp-linux-x86_64.zip
get lune https://github.com/lune-org/lune/releases/download/v0.10.5/lune-0.10.5-linux-x86_64.zip

for tool in rojo stylua selene luau-lsp lune; do
	ln -sf "$TOOLS/$tool" "$BIN/$tool"
done

lint_ready() { (cd "$(mktemp -d)" && echo 'std = "roblox"' >selene.toml && echo 'local _ = game' >x.luau && selene x.luau >/dev/null 2>&1); }

if ! lint_ready; then
	if command -v cargo >/dev/null 2>&1; then
		echo "==> Building Selene with system certificates (the release binary couldn't fetch roblox.yml)"
		SRC="$HOME/.local/src"
		mkdir -p "$SRC"
		curl -fsSL -o "$SRC/selene.tar.gz" https://static.crates.io/crates/selene/selene-0.31.0.crate
		tar xzf "$SRC/selene.tar.gz" -C "$SRC"
		sed -i 's/^features = \["json"\]$/features = ["json", "native-certs"]/' "$SRC/selene-0.31.0/Cargo.toml"
		(cd "$SRC/selene-0.31.0" && cargo build --release --quiet)
		ln -sf "$SRC/selene-0.31.0/target/release/selene" "$BIN/selene"
		lint_ready || echo "Selene still can't fetch its Roblox std: lint will fail."
	else
		echo "Selene couldn't download its Roblox std and Cargo isn't installed: lint will fail."
	fi
fi

rojo --version
stylua --version
selene --version
luau-lsp --version
lune --version
echo "Tools ready. Run ./scripts/check.sh"
