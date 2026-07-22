#!/bin/sh
# install_reticulum_config.sh
# Copies the example config to the package files share directory
# Called during `make package` or manually.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cp "$PROJECT_ROOT/config/reticulum.conf.example" \
   "$PROJECT_ROOT/pkg/files/usr/local/share/reticulum/reticulum.conf.example"

echo "Config example installed to package files."
