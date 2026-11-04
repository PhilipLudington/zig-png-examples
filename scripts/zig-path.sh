#!/bin/bash
# Prints the Zig compiler this project builds with.
# The project needs Zig 0.15 (DEBT.md Debt 1: it does not build on 0.16).
# Set ZIG to override; otherwise Homebrew's zig@0.15 is used.
ZIG="${ZIG:-/opt/homebrew/opt/zig@0.15/bin/zig}"
if [ ! -x "$ZIG" ]; then
    echo "error: Zig 0.15 not found at $ZIG (brew install zig@0.15, or set ZIG)" >&2
    exit 1
fi
VERSION=$("$ZIG" version)
case "$VERSION" in
    0.15.*) ;;
    *) echo "error: $ZIG is Zig $VERSION; this project needs 0.15" >&2; exit 1 ;;
esac
echo "$ZIG"
