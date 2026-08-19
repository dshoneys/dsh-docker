#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
  echo "DEEPSEEK_API_KEY is empty inside the container" >&2
  exit 2
fi

export DSH_PERMISSION_MODE="${DSH_PERMISSION_MODE:-danger-full-access}"
export NODE_OPTIONS="${NODE_OPTIONS:---import /fixtures/dom-polyfill.mjs}"
PROFILE=headless

dsh-reset
dsh plugin --profile "$PROFILE" add dsh-ai4scholar
dsh plugin --profile "$PROFILE" add dsh-zotero
dsh plugin --profile "$PROFILE" add dsh-plugin-writing-guard
# dsh-overleaf starts an MCP server on stdio and hijacks the headless process.
# Keep it out of the headless review run; install-smoke still covers it on web.
dsh plugin --profile "$PROFILE" add dsh-science
dsh plugin --profile "$PROFILE" list

mkdir -p /workspace/review /workspace/notes /runs/dsh-review
{
  echo "profile=$PROFILE"
  echo "permission=$DSH_PERMISSION_MODE"
  echo "key_chars=${#DEEPSEEK_API_KEY}"
  echo "started=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > /runs/dsh-review/env.txt

TASK="$(cat /fixtures/review-prompt.txt)"
set +e
dsh --profile "$PROFILE" "$TASK" > /runs/dsh-review/stdout.txt 2> /runs/dsh-review/stderr.txt
EC=$?
set -e
{
  echo "exit=$EC"
  echo "finished=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >> /runs/dsh-review/env.txt
if [[ -f /workspace/review/dsh-output.md ]]; then
  cp /workspace/review/dsh-output.md /runs/dsh-review/dsh-output.md
fi
exit "$EC"
