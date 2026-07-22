# Container for cross-compiling Rust to FreeBSD/amd64
# Uses the official cross-rs FreeBSD image.
#
# Build:
#   docker build -t opns-rns-cross cross/
#
# This is used by `cross` (https://github.com/cross-rs/cross)
# via cross.toml.  The image must include:
#   - FreeBSD sysroot at /usr/x86_64-unknown-freebsd
#   - Rust toolchain matching the host
#   - Build deps: cmake, pkg-config, libssl-dev (for crypto crates)

FROM ghcr.io/cross-rs/x86_64-unknown-freebsd:latest

# Additional build deps for crypto crates
RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*
