#!/usr/bin/env bash
# Prove the image can boot profiles without installing a third-party plugin.
set -euo pipefail

echo "node $(node -v)"
echo "pnpm $(pnpm -v)"
echo "DSH_VERSION=${DSH_VERSION:-unset}"
dsh --help >/tmp/dsh-help.txt
head -n 5 /tmp/dsh-help.txt

/opt/dsh-test/scripts/reset-home.sh

dsh plugin --profile web list
dsh --profile web --dump-config >/tmp/web-dump.yml
test -s /tmp/web-dump.yml
dsh --profile headless --dump-default-config >/tmp/headless-default.yml
test -s /tmp/headless-default.yml

echo "selfcheck ok"
