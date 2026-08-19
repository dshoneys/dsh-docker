#!/usr/bin/env bash
# Run dsh-smoke for every entry in a fixtures JSON file.
# Default: /opt/dsh-test/fixtures/research-core.json (overridden by /fixtures if mounted).
set -euo pipefail

FIXTURE="${1:-}"
if [[ -z "$FIXTURE" ]]; then
  if [[ -f /fixtures/research-core.json ]]; then
    FIXTURE=/fixtures/research-core.json
  else
    FIXTURE=/opt/dsh-test/fixtures/research-core.json
  fi
fi

if [[ ! -f "$FIXTURE" ]]; then
  echo "fixture not found: $FIXTURE" >&2
  exit 2
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
SUMMARY="/runs/${TS}-batch.json"
TMP_LIST="$(mktemp)"
node - "$FIXTURE" "$TMP_LIST" <<'NODE'
const fs = require('fs');
const data = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const plugins = data.plugins || [];
fs.writeFileSync(
  process.argv[3],
  plugins.map((p) => JSON.stringify({
    name: p.name || p.spec,
    spec: p.spec,
    expect: p.expect || '',
    profile: p.profile || '',
  })).join('\n') + (plugins.length ? '\n' : ''),
);
NODE

ok=0
fail=0
results=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" ]] && continue
  name="$(node -e 'const p=JSON.parse(process.argv[1]); process.stdout.write(p.name)' "$line")"
  spec="$(node -e 'const p=JSON.parse(process.argv[1]); process.stdout.write(p.spec)' "$line")"
  expect="$(node -e 'const p=JSON.parse(process.argv[1]); process.stdout.write(p.expect||"")' "$line")"
  profile="$(node -e 'const p=JSON.parse(process.argv[1]); process.stdout.write(p.profile||"")' "$line")"
  args=(--name "$name" "$spec")
  [[ -n "$expect" ]] && args=(--expect "$expect" "${args[@]}")
  [[ -n "$profile" ]] && args=(--profile "$profile" "${args[@]}")
  echo "=== smoke $name ($spec) ==="
  if /opt/dsh-test/scripts/smoke-install.sh "${args[@]}"; then
    ok=$((ok + 1))
    results+=("pass:$name")
  else
    fail=$((fail + 1))
    results+=("fail:$name")
  fi
done < "$TMP_LIST"
rm -f "$TMP_LIST"

node - "$SUMMARY" "$FIXTURE" "$ok" "$fail" "${results[@]}" <<'NODE'
const fs = require('fs');
const summaryPath = process.argv[2];
const fixture = process.argv[3];
const ok = Number(process.argv[4]);
const fail = Number(process.argv[5]);
const results = process.argv.slice(6).map((row) => {
  const i = row.indexOf(':');
  return { ok: row.slice(0, i) === 'pass', name: row.slice(i + 1) };
});
const report = {
  ok: fail === 0,
  fixture,
  passed: ok,
  failed: fail,
  total: ok + fail,
  results,
  finishedAt: new Date().toISOString(),
};
fs.writeFileSync(summaryPath, JSON.stringify(report, null, 2) + '\n');
process.stdout.write(JSON.stringify(report, null, 2) + '\n');
NODE

echo "batch summary: $SUMMARY"
[[ "$fail" -eq 0 ]]
