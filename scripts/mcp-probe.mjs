#!/usr/bin/env node
/**
 * Defensive loopback MCP probe (mcp_guard-compatible flags).
 * Only talks to 127.0.0.1. Does not print tool schemas or attack steps.
 */
import net from "node:net";
import fs from "node:fs";
import { execSync } from "node:child_process";

const HOST = process.env.MCP_PROBE_HOST || "127.0.0.1";
const TIMEOUT_MS = Number(process.env.MCP_PROBE_TIMEOUT_MS || 2500);

function parseArgs(argv) {
  const ports = [];
  const paths = [];
  let out = "";
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === "--ports") ports.push(...String(argv[++i] || "").split(",").map(Number).filter(Boolean));
    else if (argv[i] === "--paths") paths.push(...String(argv[++i] || "").split(",").map((p) => p.trim()).filter(Boolean));
    else if (argv[i] === "--out") out = argv[++i];
  }
  if (!ports.length) {
    const extra = process.env.MCP_PROBE_PORTS || "3080,3456,7456,7457,8090,8765,8500,8600,3111";
    ports.push(...extra.split(",").map(Number).filter(Boolean));
  }
  if (!paths.length) {
    const extra = process.env.MCP_PROBE_PATHS || "/mcp,/reef/mcp,/api/v1/mcp,/,/message";
    paths.push(...extra.split(",").map((p) => p.trim()).filter(Boolean));
  }
  return { ports: [...new Set(ports)], paths: [...new Set(paths)], out };
}

function connectOpen(port) {
  return new Promise((resolve) => {
    const socket = net.connect({ host: HOST, port });
    const timer = setTimeout(() => {
      socket.destroy();
      resolve(false);
    }, TIMEOUT_MS);
    socket.once("connect", () => {
      clearTimeout(timer);
      socket.end();
      resolve(true);
    });
    socket.once("error", () => {
      clearTimeout(timer);
      resolve(false);
    });
  });
}

function httpRaw({ port, method, path, headers, body, hostHeader }) {
  return new Promise((resolve) => {
    const socket = net.connect({ host: HOST, port });
    const timer = setTimeout(() => {
      socket.destroy();
      resolve(null);
    }, TIMEOUT_MS);
    const chunks = [];
    socket.once("error", () => {
      clearTimeout(timer);
      resolve(null);
    });
    socket.on("data", (c) => chunks.push(c));
    socket.on("end", () => {
      clearTimeout(timer);
      resolve(Buffer.concat(chunks).toString("utf8"));
    });
    socket.once("connect", () => {
      const hdrs = {
        Host: hostHeader || HOST,
        Connection: "close",
        "User-Agent": "dshoneys-mcp-probe/0.1",
        ...headers,
      };
      let req = `${method} ${path} HTTP/1.1\r\n`;
      for (const [k, v] of Object.entries(hdrs)) req += `${k}: ${v}\r\n`;
      if (body) {
        req += `Content-Length: ${Buffer.byteLength(body)}\r\n`;
      }
      req += "\r\n";
      if (body) req += body;
      socket.write(req);
    });
  });
}

function parseHttp(raw) {
  if (!raw) return null;
  const split = raw.includes("\r\n\r\n") ? "\r\n\r\n" : "\n\n";
  const idx = raw.indexOf(split);
  const head = idx >= 0 ? raw.slice(0, idx) : raw;
  const body = idx >= 0 ? raw.slice(idx + split.length) : "";
  const lines = head.split(/\r?\n/);
  const statusLine = lines[0] || "";
  const headers = {};
  for (const line of lines.slice(1)) {
    const i = line.indexOf(":");
    if (i > 0) headers[line.slice(0, i).trim().toLowerCase()] = line.slice(i + 1).trim();
  }
  return { statusLine, headers, body };
}

function extractJson(body) {
  const trimmed = body.trim();
  if (trimmed.startsWith("{")) return trimmed;
  for (const line of body.split(/\r?\n/)) {
    const rest = line.trim().replace(/^data:\s*/, "");
    if (rest.startsWith("{")) return rest;
  }
  const i = trimmed.indexOf("{");
  return i >= 0 ? trimmed.slice(i) : "";
}

function classifyMcp(path, raw) {
  const http = parseHttp(raw);
  if (!http || !/^HTTP\/1\./.test(http.statusLine)) return null;
  if (/\b401\b|\b403\b/.test(http.statusLine)) {
    return { protected: true, endpoint: path, toolCount: 0, sampleTools: [] };
  }
  const jsonText = extractJson(http.body);
  let parsed;
  try {
    parsed = JSON.parse(jsonText);
  } catch {
    return null;
  }
  if (parsed?.jsonrpc !== "2.0") return null;
  const tools = parsed?.result?.tools;
  if (Array.isArray(tools)) {
    return {
      protected: false,
      endpoint: path,
      toolCount: tools.length,
      sampleTools: tools.map((t) => t?.name).filter(Boolean).slice(0, 8),
    };
  }
  if (parsed.result || parsed.error) {
    return { protected: false, endpoint: path, toolCount: 0, sampleTools: [] };
  }
  return null;
}

function listeners() {
  try {
    return execSync("ss -lnt 2>/dev/null || netstat -lnt 2>/dev/null", {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
  } catch {
    return "";
  }
}

function bindOf(port, table) {
  const re = new RegExp(`(?:\\s|:)${port}\\s`);
  const hits = table.split(/\r?\n/).filter((line) => line.includes(`:${port}`) || re.test(line));
  const addrs = [];
  for (const line of hits) {
    const m = line.match(/(?:(\d+\.\d+\.\d+\.\d+|\[::\]|::|\*):(\d+))/g);
    if (m) addrs.push(...m);
  }
  const wildcard = addrs.some((a) => a.startsWith("0.0.0.0:") || a.startsWith("*:") || a.startsWith("[::]:") || a.startsWith(":::"));
  return { addrs, wildcard };
}

async function probePort(port, table, paths) {
  const open = await connectOpen(port);
  const bind = bindOf(port, table);
  if (!open) {
    return { port, open: false, bind, http: null, mcp: null, riskFlags: [] };
  }
  const getRaw = await httpRaw({ port, method: "GET", path: "/", headers: { Accept: "*/*" } });
  const http = parseHttp(getRaw);
  let mcp = null;
  for (const path of paths) {
    const body = JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} });
    const raw = await httpRaw({
      port,
      method: "POST",
      path,
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json, text/event-stream",
        "MCP-Protocol-Version": "2025-03-26",
      },
      body,
    });
    mcp = classifyMcp(path, raw);
    if (mcp) break;
  }
  let hostRejected = null;
  if (mcp && !mcp.protected) {
    const body = JSON.stringify({ jsonrpc: "2.0", id: 2, method: "tools/list", params: {} });
    const raw = await httpRaw({
      port,
      method: "POST",
      path: mcp.endpoint,
      hostHeader: "not-localhost.invalid",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json, text/event-stream",
        "MCP-Protocol-Version": "2025-03-26",
      },
      body,
    });
    const rebound = classifyMcp(mcp.endpoint, raw);
    hostRejected = !(rebound && !rebound.protected);
  }
  const acao = http?.headers["access-control-allow-origin"] || "";
  const riskFlags = [];
  if (mcp && !mcp.protected) {
    riskFlags.push(mcp.toolCount > 0 ? "mcp_tools_exposed" : "mcp_jsonrpc_surface");
    if (acao.trim() === "*") riskFlags.push("cors_star");
    if (!http?.headers["www-authenticate"]) riskFlags.push("no_www_authenticate_hint");
    if (bind.wildcard) riskFlags.push("bind_wildcard");
    if (hostRejected === false) riskFlags.push("host_header_not_validated");
  }
  return {
    port,
    open: true,
    bind,
    http: http
      ? {
          statusLine: http.statusLine,
          acao: acao || null,
          wwwAuthenticate: http.headers["www-authenticate"] || null,
        }
      : null,
    mcp,
    hostRejected,
    riskFlags,
  };
}

const { ports, paths, out } = parseArgs(process.argv);
const table = listeners();
const findings = [];
for (const port of ports) findings.push(await probePort(port, table, paths));

const report = {
  host: HOST,
  scannedAt: new Date().toISOString(),
  findings,
  summary: {
    open: findings.filter((f) => f.open).length,
    mcpRisk: findings.filter((f) => f.riskFlags.length).length,
  },
};
const text = JSON.stringify(report, null, 2) + "\n";
if (out) fs.writeFileSync(out, text);
process.stdout.write(text);
process.exit(0);
