#!/bin/sh
# build.sh — Cross-compile rnsd for FreeBSD/amd64
#
# Prerequisites:
#   rustup target add x86_64-unknown-freebsd
#   cargo install cross   (recommended; handles sysroot)
#
# Usage:
#   ./rnsd/build.sh           # use cross-rs (Docker-based)
#   ./rnsd/build.sh --local   # use local rustc + freebsd target
#
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RNSD_SRC="$(cd "$PROJECT_ROOT/../Reticulum-rust" && pwd)"
OUTPUT="$PROJECT_ROOT/pkg/files/usr/local/bin/rnsd"

TARGET="x86_64-unknown-freebsd"

echo "=== rnsd cross-compile for $TARGET ==="

if [ "${1:-}" = "--local" ]; then
    echo "Using local rustc (requires $TARGET toolchain)"
    cd "$RNSD_SRC"
    cargo build --release \
        --target "$TARGET" \
        --no-default-features \
        -p reticulum_rust
    cp "$RNSD_SRC/target/$TARGET/release/rnsd" "$OUTPUT"
else
    echo "Using cross-rs (Docker-based)"
    cd "$RNSD_SRC"
    cross build --release \
        --target "$TARGET" \
        --no-default-features \
        -p reticulum_rust
    cp "$RNSD_SRC/target/$TARGET/release/rnsd" "$OUTPUT"
fi

echo "=== Built: $OUTPUT ==="
file "$OUTPUT" 2>/dev/null || true
