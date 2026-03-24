#!/bin/bash
# Wrapper to ensure node is on PATH when Chrome launches the native host.
# Chrome uses a minimal environment that may not include Homebrew paths.

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:$PATH"

exec node "$(dirname "$0")/sidecar-host.cjs" "$@"
