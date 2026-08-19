#!/usr/bin/env bash
# Install one plugin into a clean web (or headless) profile and prove it
# composed, without booting an agent. Zero model tokens.
set -euo pipefail

: "${DSH_HOME:=/dsh-home}"
: "${DSH_PROFILE:=web}"

PROFILE="$DSH_PROFILE"
RESET=1
SPEC=""
EXPECT=""
NAME=""

usage() {
  cat <<'EOF'
Usage: dsh-smoke [options] <pnpm-spec>

  dsh-smoke dsh-ai4scholar
  dsh-smoke github:literaf/dsh-ai4scholar
  dsh-smoke --expect dsh-zotero dsh-zotero
  dsh-smoke --profile headless --name writing-guard dsh-plugin-writing-guard

Options:
  --profile NAME   web (default) or headless
  --expect NEEDLE  string that must appear in dump-config / plugin list
  --name LABEL     used in /runs/<timestamp>-<label>/
  --no-reset       keep the current $DSH_HOME (for stacking plugins)
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --expect)
      EXPECT="$2"
      shift 2
      ;;
    --name)
      NAME="$2"
      shift 2
      ;;
    --no-reset)
      RESET=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      SPEC="${*:-}"
      break
      ;;
    -*)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$SPEC" ]]; then
        echo "unexpected extra argument: $1" >&2
        exit 2
      fi
      SPEC="$1"
      shift
      ;;
  esac
done

if [[ -z "$SPEC" ]]; then
  usage >&2
  exit 2
fi

slug_of() {
  echo "$1" | sed -E 's#^github:##; s#[^A-Za-z0-9._-]+#-#g; s#^-##; s#-$##'
}

NEEDLE="${EXPECT:-$(echo "$SPEC" | sed -E 's#^github:[^/]+/##' | sed -E 's#[@#].*$##')}"
NAME="${NAME:-$(slug_of "$SPEC")}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/runs/${TS}-${NAME}"
mkdir -p "$OUT"

if [[ "$RESET" -eq 1 ]]; then
  /opt/dsh-test/scripts/reset-home.sh | tee "$OUT/reset.log"
fi

echo "$SPEC" >"$OUT/spec.txt"
{
  echo "spec=$SPEC"
  echo "profile=$PROFILE"
  echo "dsh=$(command -v dsh)"
  echo "node=$(node -v)"
  echo "pnpm=$(pnpm -v)"
  echo "DSH_HOME=$DSH_HOME"
  echo "DSH_VERSION=${DSH_VERSION:-unknown}"
} >"$OUT/env.txt"

set +e
dsh plugin --profile "$PROFILE" list >"$OUT/list-before.txt" 2>&1
LIST_BEFORE_EC=$?

# Forward extra pnpm flags after the spec. ignore-scripts=false so prepare/build
# of GitHub plugins actually runs; this image already allow-builds globally.
dsh plugin --profile "$PROFILE" add "$SPEC" >"$OUT/install.log" 2>&1
ADD_EC=$?

dsh plugin --profile "$PROFILE" list >"$OUT/list-after.txt" 2>&1
LIST_AFTER_EC=$?

dsh --profile "$PROFILE" --dump-config >"$OUT/dump-config.yml" 2>"$OUT/dump-config.err"
DUMP_EC=$?
set -e

if [[ -f "$DSH_HOME/profiles/$PROFILE/package.json" ]]; then
  cp "$DSH_HOME/profiles/$PROFILE/package.json" "$OUT/profile-package.json"
fi

LIST_HIT=0
DUMP_HIT=0
PKG_HIT=0
grep -Fqi -- "$NEEDLE" "$OUT/list-after.txt" && LIST_HIT=1 || true
grep -Fqi -- "$NEEDLE" "$OUT/dump-config.yml" && DUMP_HIT=1 || true
if [[ -f "$OUT/profile-package.json" ]]; then
  grep -Fqi -- "$NEEDLE" "$OUT/profile-package.json" && PKG_HIT=1 || true
fi

PASS=0
REASON=""
if [[ "$ADD_EC" -eq 0 && ( "$LIST_HIT" -eq 1 || "$DUMP_HIT" -eq 1 || "$PKG_HIT" -eq 1 ) && "$DUMP_EC" -eq 0 ]]; then
  PASS=1
  REASON="installed and visible in dump-config or plugin list"
elif [[ "$ADD_EC" -ne 0 ]]; then
  REASON="dsh plugin add exited $ADD_EC"
elif [[ "$DUMP_EC" -ne 0 ]]; then
  REASON="dump-config exited $DUMP_EC after a successful add"
else
  REASON="add succeeded but needle '$NEEDLE' not found in list/dump/package.json"
fi

node - "$OUT" "$SPEC" "$PROFILE" "$NEEDLE" "$NAME" "$PASS" "$REASON" "$ADD_EC" "$DUMP_EC" "$LIST_HIT" "$DUMP_HIT" "$PKG_HIT" <<'NODE'
const fs = require('fs');
const path = require('path');
const [
  , , out, spec, profile, needle, name, pass, reason, addEc, dumpEc, listHit, dumpHit, pkgHit
] = process.argv;
const report = {
  ok: pass === '1',
  name,
  spec,
  profile,
  needle,
  reason,
  exit: {
    add: Number(addEc),
    dumpConfig: Number(dumpEc),
  },
  hits: {
    pluginList: listHit === '1',
    dumpConfig: dumpHit === '1',
    profilePackage: pkgHit === '1',
  },
  dshVersion: process.env.DSH_VERSION || null,
  finishedAt: new Date().toISOString(),
  dir: out,
};
fs.writeFileSync(path.join(out, 'result.json'), JSON.stringify(report, null, 2) + '\n');
process.stdout.write(JSON.stringify(report, null, 2) + '\n');
NODE

echo "$OUT" > /runs/latest-path.txt
ln -sfn "$OUT" /runs/latest || true

if [[ "$PASS" -ne 1 ]]; then
  echo "FAIL: $REASON" >&2
  echo "logs: $OUT/install.log" >&2
  exit 1
fi
