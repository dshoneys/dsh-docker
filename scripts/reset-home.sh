#!/usr/bin/env bash
set -euo pipefail

: "${DSH_HOME:=/dsh-home}"

rm -rf "${DSH_HOME:?}/profiles" \
  "${DSH_HOME}/cordis.patch.yml" \
  "${DSH_HOME}/sessions" \
  "${DSH_HOME}/logs" || true
mkdir -p "$DSH_HOME"
cp -a /opt/dsh-templates/. "$DSH_HOME/"
echo "reset DSH_HOME=$DSH_HOME from /opt/dsh-templates"
