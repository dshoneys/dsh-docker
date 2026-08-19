#!/usr/bin/env node
/**
 * Docs/source audit for MCP bind + auth claims. Network fetch of public GitHub only.
 */
import fs from "node:fs";

const fixturePath = process.argv[2] || "/opt/dsh-test/fixtures/mcp-plugins.json";
const outPath = process.argv[3] || "";
const data = JSON.parse(fs.readFileSync(fixturePath, "utf8"));

const BIND_WILDCARD = /\b(?:0\.0\.0\.0|::\s*,?\s*listen|host:\s*['"]0\.0\.0\.0['"])\b/;
const BIND_LOOPBACK = /\b127\.0\.0\.1\b|\blocalhost\b/;
const CORS_STAR = /Access-Control-Allow-Origin['":\s]*\*/i;
const AUTH = /\b(?:authToken|bearer|www-authenticate|authorization|oauth|pkce)\b/i;

async function fetchText(url) {
  const res = await fetch(url, { headers: { "user-agent": "dshoneys-dsh-docker-audit" } });
  if (!res.ok) return { ok: false, status: res.status, text: "" };
  return { ok: true, status: res.status, text: await res.text() };
}

async function auditOne(plugin) {
  const rawBase = `https://raw.githubusercontent.com/${plugin.github}/HEAD`;
  const files = ["README.md", "README.zh.md", "README.en.md"];
  const blobs = [];
  for (const file of files) {
    const got = await fetchText(`${rawBase}/${file}`);
    if (got.ok) blobs.push({ file, text: got.text.slice(0, 80_000) });
  }
  const joined = blobs.map((b) => b.text).join("\n");
  const flags = [];
  if (!joined) flags.push("docs_unreadable");
  if (joined && BIND_WILDCARD.test(joined) && !/do not bind|不要绑|never.*0\.0\.0\.0/i.test(joined)) {
    flags.push("docs_mention_wildcard_bind");
  }
  if (joined && BIND_LOOPBACK.test(joined)) flags.push("docs_claim_loopback");
  if (joined && CORS_STAR.test(joined)) flags.push("docs_cors_star");
  if (joined && /\b(?:LAN|0\.0\.0\.0|any device on your LAN|public-base-url)\b/i.test(joined)) {
    flags.push("docs_lan_or_public_expose");
  }
  if (plugin.kind?.startsWith("http-mcp") && joined && !AUTH.test(joined)) {
    flags.push("docs_no_auth_mention");
  }
  return {
    name: plugin.name,
    github: plugin.github,
    kind: plugin.kind,
    defaultBind: plugin.defaultBind || null,
    ports: plugin.ports || [],
    live: Boolean(plugin.live),
    flags,
    docsFiles: blobs.map((b) => b.file),
  };
}

const results = [];
for (const plugin of data.plugins || []) {
  results.push(await auditOne(plugin));
}

const report = {
  fixture: fixturePath,
  scannedAt: new Date().toISOString(),
  results,
};
const text = JSON.stringify(report, null, 2) + "\n";
if (outPath) fs.writeFileSync(outPath, text);
process.stdout.write(text);
