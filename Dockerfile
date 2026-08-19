# DSH plugin installability sandbox.
# Pin the harness version; keep $DSH_HOME off the host profile.
ARG NODE_IMAGE=node:22-bookworm-slim
FROM ${NODE_IMAGE}

ARG DSH_VERSION=0.1.0-rc.7
ENV DSH_VERSION=${DSH_VERSION}
ENV DSH_HOME=/dsh-home
ENV PNPM_HOME=/pnpm
ENV PNPM_STORE_DIR=/pnpm-store
ENV PATH="${PNPM_HOME}:${PATH}"
ENV CI=true
ENV npm_config_update_notifier=false
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    iproute2 \
    python3 \
    tini \
  && rm -rf /var/lib/apt/lists/* \
  && git config --system --add safe.directory '*'

# pnpm is what `dsh plugin` forwards to. Corepack ships with Node 22.
RUN corepack enable \
  && corepack prepare pnpm@10.15.0 --activate \
  && mkdir -p /pnpm /pnpm-store /dsh-home /workspace /runs \
  && pnpm config set store-dir /pnpm-store --global \
  && pnpm config set dangerouslyAllowAllBuilds true --global

# Global CLI is enough for plugin add + dump-config. No host ~/.dsh.
RUN npm install -g --no-fund --no-audit "@deepseek-ai/dsh@${DSH_VERSION}" \
  && dsh --help >/dev/null

# Seed empty web + headless profiles into a template copied on each reset.
# First dump forces the shipped profile templates onto disk.
ENV DSH_HOME=/opt/dsh-templates
RUN mkdir -p /opt/dsh-templates \
  && dsh --profile web --dump-default-config >/tmp/web-default.yml \
  && dsh --profile headless --dump-default-config >/tmp/headless-default.yml \
  && dsh plugin --profile web list >/tmp/web-list.txt \
  && dsh plugin --profile headless list >/tmp/headless-list.txt \
  && test -f /opt/dsh-templates/profiles/web/package.json \
  && test -f /opt/dsh-templates/profiles/headless/package.json
ENV DSH_HOME=/dsh-home

COPY scripts /opt/dsh-test/scripts
COPY fixtures /opt/dsh-test/fixtures
RUN sed -i 's/\r$//' /opt/dsh-test/scripts/*.sh \
  && chmod +x /opt/dsh-test/scripts/*.sh \
  && ln -sf /opt/dsh-test/scripts/smoke-install.sh /usr/local/bin/dsh-smoke \
  && ln -sf /opt/dsh-test/scripts/reset-home.sh /usr/local/bin/dsh-reset \
  && ln -sf /opt/dsh-test/scripts/batch-smoke.sh /usr/local/bin/dsh-batch-smoke \
  && ln -sf /opt/dsh-test/scripts/selfcheck.sh /usr/local/bin/dsh-selfcheck \
  && ln -sf /opt/dsh-test/scripts/mcp-audit.sh /usr/local/bin/dsh-mcp-audit

WORKDIR /workspace
# Compose already injects tini via `init: true`; do not nest another tini.
ENTRYPOINT ["/opt/dsh-test/scripts/entrypoint.sh"]
CMD ["bash"]
