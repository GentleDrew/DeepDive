#!/usr/bin/env bash
# Full verification: strict type check, formatting, unit tests, place build and runtime smoke tests.
# Requires rojo, luau-lsp, stylua and lune on PATH (`rokit install`).
set -euo pipefail
cd "$(dirname "$0")/.."

DEFS="tools/globalTypes.d.luau"
if [ ! -f "$DEFS" ]; then
	echo "Downloading Roblox type definitions for luau-lsp..."
	curl -fsSL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi

echo "== Type check (luau-lsp, strict)"
rojo sourcemap default.project.json -o sourcemap.json --include-non-scripts
luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --defs=@roblox="$DEFS" src

echo "== Formatting (StyLua)"
stylua --check src tests

echo "== Unit tests"
lune run tests/run.luau

echo "== Build place"
rojo build default.project.json -o DeepDive.rbxlx

echo "== Runtime smoke test (desktop)"
lune run tests/smoke.luau

echo "== Runtime smoke test (mobile)"
lune run tests/smoke.luau --mobile

echo "All checks passed."
