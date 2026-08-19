#!/usr/bin/env bash
# Classify MCP surfaces, optionally boot live HTTP-MCP plugins, then probe loopback.
# Defensive checks only (mcp_guard-compatible flags).
set -euo pipefail

: "${DSH_HOME:=/dsh-home}"
# MCP HTTP plugins load with `dsh web`; ignore compose's default headless profile.
DSH_PROFILE="${MCP_AUDIT_PROFILE:-web}"
FIXTURE="${1:-}"
if [[ -z "$FIXTURE" ]]; then
  if [[ -f /fixtures/mcp-plugins.json ]]; then
    FIXTURE=/fixtures/mcp-plugins.json
  else
    FIXTURE=/opt/dsh-test/fixtures/mcp-plugins.json
  fi
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/runs/${TS}-mcp-audit"
mkdir -p "$OUT"
echo "$FIXTURE" >"$OUT/fixture.txt"

/opt/dsh-test/scripts/reset-home.sh | tee "$OUT/reset.log"

echo "=== source/docs audit ==="
node /opt/dsh-test/scripts/mcp-source-audit.mjs "$FIXTURE" "$OUT/source-audit.json"

LIVE_SPECS="$(node - "$FIXTURE" <<'NODE'
const d = require(process.argv[2]);
const specs = (d.plugins || []).filter((p) => p.live && p.spec).map((p) => p.spec);
process.stdout.write(specs.join('\n'));
NODE
)"

if [[ -n "$LIVE_SPECS" ]]; then
  echo "=== install live MCP plugins ==="
  while IFS= read -r spec; do
    [[ -z "$spec" ]] && continue
    echo "add $spec"
    set +e
    dsh plugin --profile "$DSH_PROFILE" add "$spec" >>"$OUT/install.log" 2>&1
    echo "add $spec exit=$?" >>"$OUT/install.log"
    set -e
  done <<< "$LIVE_SPECS"
fi

echo "=== dump-config ==="
set +e
dsh --profile "$DSH_PROFILE" --dump-config >"$OUT/dump-config.yml" 2>"$OUT/dump-config.err"
set -e

echo "=== plugin list ==="
set +e
dsh plugin --profile "$DSH_PROFILE" list >"$OUT/plugin-list.txt" 2>&1
set -e

echo "=== boot dsh web briefly ==="
set +e
timeout 45 dsh --profile "$DSH_PROFILE" web --port 3080 >"$OUT/web.log" 2>&1 &
WEB_PID=$!
sleep 18
ss -lnt >"$OUT/listeners.txt" 2>&1 || netstat -lnt >"$OUT/listeners.txt" 2>&1
node /opt/dsh-test/scripts/mcp-probe.mjs --ports 3080,3456,7456,7457,8090,8765 --out "$OUT/probe.json"
kill "$WEB_PID" >/dev/null 2>&1
wait "$WEB_PID" >/dev/null 2>&1
set -e

node - "$OUT" <<'NODE'
const fs = require('fs');
const path = require('path');
const out = process.argv[2];
const source = JSON.parse(fs.readFileSync(path.join(out, 'source-audit.json'), 'utf8'));
const probe = JSON.parse(fs.readFileSync(path.join(out, 'probe.json'), 'utf8'));
const summary = {
  ok: true,
  dir: out,
  sourceFlags: source.results.flatMap((r) => r.flags.map((f) => `${r.name}:${f}`)),
  openPorts: probe.findings.filter((f) => f.open).map((f) => f.port),
  mcpRisk: probe.findings.filter((f) => f.riskFlags.length),
  finishedAt: new Date().toISOString(),
};
fs.writeFileSync(path.join(out, 'result.json'), JSON.stringify(summary, null, 2) + '\n');
process.stdout.write(JSON.stringify(summary, null, 2) + '\n');
NODE

echo "$OUT" > /runs/latest-path.txt
ln -sfn "$OUT" /runs/latest || true
echo "mcp-audit done: $OUT"
