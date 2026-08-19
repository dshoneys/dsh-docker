param(
  [Parameter(Position = 0)]
  [string]$Command = "help",
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Rest
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

function Invoke-Dsh {
  docker compose run --rm dsh @args
}

switch ($Command) {
  "help" {
    @"
dsh-test.ps1 build
dsh-test.ps1 selfcheck
dsh-test.ps1 smoke <spec> [extra dsh-smoke args]
dsh-test.ps1 batch [fixture.json]
dsh-test.ps1 mcp-audit
dsh-test.ps1 sh
dsh-test.ps1 web
"@
  }
  "build" { docker compose build @Rest }
  "selfcheck" { Invoke-Dsh dsh-selfcheck }
  "smoke" { Invoke-Dsh dsh-smoke @Rest }
  "batch" { Invoke-Dsh dsh-batch-smoke @Rest }
  "mcp-audit" { docker compose run --rm -e DSH_PROFILE=web -e MCP_AUDIT_PROFILE=web dsh dsh-mcp-audit @Rest }
  "sh" { Invoke-Dsh bash }
  "web" { docker compose run --rm --service-ports dsh dsh web --port 3080 }
  default {
    Write-Error "unknown command: $Command"
  }
}
