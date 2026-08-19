#!/usr/bin/env bash
set -euo pipefail

: "${DSH_HOME:=/dsh-home}"
: "${PNPM_STORE_DIR:=/pnpm-store}"

mkdir -p "$DSH_HOME" "$PNPM_STORE_DIR" /runs /workspace
pnpm config set store-dir "$PNPM_STORE_DIR" --global >/dev/null

# Fresh tmpfs home: copy the empty profiles baked into the image.
if [[ ! -f "$DSH_HOME/profiles/web/package.json" ]]; then
  cp -a /opt/dsh-templates/. "$DSH_HOME/"
fi

if [[ $# -eq 0 ]]; then
  exec bash
fi
exec "$@"
