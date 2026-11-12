#!/usr/bin/env bash
# bootstrap-agent.sh - one-time per-user setup
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$HERE/opencode"

PORT=$(( 20000 + $(id -u) % 40000 ))
if ss -ltn | grep -q ":$PORT "; then
  echo "port $PORT is already in use; pick another" >&2; exit 1
fi

TMP_MOUNTS="$(mktemp)"; trap 'rm -f "$TMP_MOUNTS"' EXIT
echo "@HERE/opencode:~/.config/opencode:rw" > "$TMP_MOUNTS"

MOUNTS_FILE="$TMP_MOUNTS" "$HERE/run-agent.sh" --no-conda \
  env opencode service set port "$PORT"

# launches opencode. Once it launches quit
