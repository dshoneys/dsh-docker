#!/usr/bin/env bash
# Classify MCP surfaces, optionally boot live HTTP-MCP plugins, then probe loopback.
# Defensive checks only (mcp_guard-compatible flags).
# Live plugins are installed one-at-a-time so peer deps cannot collapse the tree.
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
mkdir -p "$OUT/live"
echo "$FIXTURE" >"$OUT/fixture.txt"
export DSH_PROFILE

echo "=== source/docs audit ==="
node /opt/dsh-test/scripts/mcp-source-audit.mjs "$FIXTURE" "$OUT/source-audit.json"

LIVE_JSON="$(node - "$FIXTURE" <<'NODE'
const d = require(process.argv[2]);
const rows = (d.plugins || []).filter((p) => p.live && p.spec);
process.stdout.write(JSON.stringify(rows));
NODE
)"
echo "$LIVE_JSON" >"$OUT/live-plugins.json"

DEFAULT_PATHS="/mcp,/reef/mcp,/api/v1/mcp,/,/message"

probe_one() {
  local name="$1" spec="$2" ports="$3" paths="$4"
  local dir="$OUT/live/$name"
  mkdir -p "$dir"
  echo "=== live $name ($spec) ==="
  /opt/dsh-test/scripts/reset-home.sh >"$dir/reset.log" 2>&1
  set +e
  dsh plugin --profile "$DSH_PROFILE" add "$spec" >"$dir/install.log" 2>&1
  echo "add exit=$?" >>"$dir/install.log"
  dsh plugin --profile "$DSH_PROFILE" list >"$dir/plugin-list.txt" 2>&1
  dsh --profile "$DSH_PROFILE" --dump-config >"$dir/dump-config.yml" 2>"$dir/dump-config.err"
  timeout 45 dsh web --port 3080 >"$dir/web.log" 2>&1 &
  local web_pid=$!
  sleep 18
  ss -lnt >"$dir/listeners.txt" 2>&1 || netstat -lnt >"$dir/listeners.txt" 2>&1
  node /opt/dsh-test/scripts/mcp-probe.mjs --ports "$ports" --paths "$paths" --out "$dir/probe.json"
  kill "$web_pid" >/dev/null 2>&1
  wait "$web_pid" >/dev/null 2>&1
  set -e
}

node - "$OUT/live-plugins.json" >"$OUT/live-rows.tsv" <<'NODE'
const fs = require('fs');
const rows = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
for (const p of rows) {
  const ports = [3080, ...(p.ports || [])].filter(Boolean);
  const paths = ['/mcp', '/reef/mcp', '/', ...(p.paths || [])];
  process.stdout.write([p.name, p.spec, [...new Set(ports)].join(','), [...new Set(paths)].join(',')].join('\t') + '\n');
}
NODE

if [[ -s "$OUT/live-rows.tsv" ]]; then
  while IFS=$'\t' read -r name spec ports paths; do
    [[ -z "$name" ]] && continue
    probe_one "$name" "$spec" "$ports" "${paths:-$DEFAULT_PATHS}"
  done <"$OUT/live-rows.tsv"
fi

node - "$OUT" <<'NODE'
const fs = require('fs');
const path = require('path');
const out = process.argv[2];
const source = JSON.parse(fs.readFileSync(path.join(out, 'source-audit.json'), 'utf8'));
const liveDir = path.join(out, 'live');
const live = [];
if (fs.existsSync(liveDir)) {
  for (const name of fs.readdirSync(liveDir)) {
    const probePath = path.join(liveDir, name, 'probe.json');
    const webLog = path.join(liveDir, name, 'web.log');
    if (!fs.existsSync(probePath)) continue;
    const probe = JSON.parse(fs.readFileSync(probePath, 'utf8'));
    live.push({
      name,
      webBooted: fs.existsSync(webLog) && /dsh web: http/.test(fs.readFileSync(webLog, 'utf8')),
      openPorts: probe.findings.filter((f) => f.open).map((f) => f.port),
      mcpRisk: probe.findings.filter((f) => f.riskFlags.length),
    });
  }
}
const summary = {
  ok: true,
  dir: out,
  sourceFlags: source.results.flatMap((r) => r.flags.map((f) => `${r.name}:${f}`)),
  live,
  openPorts: [...new Set(live.flatMap((l) => l.openPorts))],
  mcpRisk: live.flatMap((l) => l.mcpRisk.map((f) => ({ plugin: l.name, ...f }))),
  finishedAt: new Date().toISOString(),
};
fs.writeFileSync(path.join(out, 'result.json'), JSON.stringify(summary, null, 2) + '\n');
process.stdout.write(JSON.stringify(summary, null, 2) + '\n');
NODE

echo "$OUT" > /runs/latest-path.txt
ln -sfn "$OUT" /runs/latest || true
echo "mcp-audit done: $OUT"
