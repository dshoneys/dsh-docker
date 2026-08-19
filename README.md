# dsh-docker

Isolated installability **and MCP loopback** sandbox for DeepSeek Harness plugins.

Org: [dshoneys](https://github.com/dshoneys) · sister tool: [mcp_guard](https://github.com/dshoneys/mcp_guard)

The image pins `@deepseek-ai/dsh`, keeps `$DSH_HOME` on a tmpfs (never your host `~/.dsh`), and proves a plugin composed with `--dump-config`. That step does not boot a model, so it does not spend tokens.

## What it is for

- Repeat `dsh plugin add` without polluting the real profile
- Same Node / pnpm / dsh version on every run
- Cache the pnpm store so the 2nd install of the same spec is cheap
- Later: optional `dsh web` or `dsh --profile headless "..."` with keys in `.env`

## Build

Needs Docker Desktop. From this directory:

```powershell
docker compose build
docker compose run --rm dsh dsh-selfcheck
```

Default pin is `0.1.0-rc.7`. Override:

```powershell
$env:DSH_VERSION = "0.1.0-rc.6"
docker compose build --build-arg DSH_VERSION=$env:DSH_VERSION
```

## Install smoke (no model)

One plugin, clean home each time:

```powershell
docker compose run --rm dsh dsh-smoke dsh-ai4scholar
docker compose run --rm dsh dsh-smoke github:Vncntvx/dsh-zotero
docker compose run --rm dsh dsh-smoke --expect writing-guard dsh-plugin-writing-guard
```

Stack two plugins in the same home (`--no-reset` on the second):

```powershell
docker compose run --rm dsh bash -lc "dsh-smoke dsh-ai4scholar && dsh-smoke --no-reset dsh-zotero"
```

Shortlist batch (research core five):

```powershell
docker compose run --rm dsh dsh-batch-smoke
```

Each run writes `runs/<utc>-<name>/`:

| file | meaning |
| --- | --- |
| `result.json` | pass/fail, needle hits, exit codes |
| `install.log` | `dsh plugin add` stdout/stderr |
| `dump-config.yml` | composed tree, no boot |
| `profile-package.json` | profile lock after add |

`runs/latest` points at the last smoke.

## MCP surface audit (defensive)

Checks whether a plugin opens an unauthenticated HTTP MCP on loopback. Flags match [mcp_guard](https://github.com/dshoneys/mcp_guard): `mcp_tools_exposed`, `mcp_jsonrpc_surface`, `cors_star`, `no_www_authenticate_hint`, plus `bind_wildcard` / `host_header_not_validated`.

Does **not** run exploit payloads. `tools/list` without a token is an auth check; tool schemas are not dumped.

```powershell
docker compose run --rm dsh dsh-mcp-audit
```

Fixture: `fixtures/mcp-plugins.json` (high-star UIs + reverse HTTP MCP bridges + stdio MCP + MCP-client managers). Live install is only `live: true` HTTP bridges.

Each run writes `runs/<utc>-mcp-audit/` (`source-audit.json`, `probe.json`, `listeners.txt`, `result.json`).

## Optional web UI

Does not need a key just to boot the UI. Keys only if you later send an agent turn.

```powershell
docker compose run --rm --service-ports dsh dsh web --port 3080
```

Then http://127.0.0.1:3080/

Copy `.env.example` to `.env` when you want API keys inside the container.

## Layout

| path | role |
| --- | --- |
| `/opt/dsh-templates` | empty web + headless profiles baked at image build |
| `/dsh-home` | tmpfs working `$DSH_HOME`; reset from the template |
| `/pnpm-store` | named volume, survives containers |
| `/workspace` | bind of `./workspace` |
| `/runs` | bind of `./runs` |

## Commands inside the container

| command | does |
| --- | --- |
| `dsh-selfcheck` | version + empty dump-config |
| `dsh-mcp-audit` | docs + live loopback MCP probe |
| `dsh-reset` | restore empty profiles |
| `dsh-smoke <spec>` | reset, add, dump-config, write `result.json` |
| `dsh-batch-smoke [file]` | smoke every entry in a fixtures JSON |

## Not in v1

- Native toolchain (`g++` / `make`) — add only if a plugin's `prepare` needs it
- Source-tree dsh (this image uses the published npm CLI)
- Automatic agent-turn eval — install smoke is the gate; model tests stay opt-in
