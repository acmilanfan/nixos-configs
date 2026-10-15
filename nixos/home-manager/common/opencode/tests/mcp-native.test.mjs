// Verifies the codebase-memory access fix: with a project MCP server configured
// `codemode: false`, its read-only tools appear on the provider's native tool
// list, so a read-only agent that denies Code Mode (`execute`) can still use
// them. Uses an isolated service, a fixture MCP stdio server, and a fixture
// provider; no live model or real index is touched.
//
// Usage (same env as runtime.test.mjs):
//   OPENCODE_TEST_HOME=... OPENCODE_TEST_BIN=... \
//     node nixos/home-manager/common/opencode/tests/mcp-native.test.mjs
import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, writeFile, readFile, open, rm } from "node:fs/promises";
import { resolve } from "node:path";
import { createServer } from "node:http";
import { fileURLToPath } from "node:url";
import { createRequest } from "../vicinae-storage.mjs";

const execute = promisify(execFile);
const root = process.env.OPENCODE_TEST_HOME;
const bin = process.env.OPENCODE_TEST_BIN;
// Integration suite: skip (not fail) without a prepared test environment.
const skip = (!root || !bin) && "Set OPENCODE_TEST_HOME and OPENCODE_TEST_BIN";
const project = skip ? "" : resolve(root, "mcp-project");
let child, log, request, env, provider;
const modelRequests = [];

// Minimal MCP server over stdio exposing one read and one admin tool.
const MCP_FIXTURE = `
const tools = [
  { name: "read_thing", description: "read", inputSchema: { type: "object", properties: {} } },
  { name: "admin_thing", description: "admin", inputSchema: { type: "object", properties: {} } },
];
const respond = (id, result) => process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\\n");
let buffer = "";
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  let newline;
  while ((newline = buffer.indexOf("\\n")) !== -1) {
    const line = buffer.slice(0, newline);
    buffer = buffer.slice(newline + 1);
    if (!line.trim()) continue;
    const message = JSON.parse(line);
    if (message.method === "initialize") respond(message.id, { protocolVersion: "2024-11-05", capabilities: { tools: {} }, serverInfo: { name: "mcp-fixture", version: "1" } });
    else if (message.method === "tools/list") respond(message.id, { tools });
    else if (message.id !== undefined) respond(message.id, {});
  }
});
`;

before(async () => {
  if (skip) return;
  env = {
    ...process.env, HOME: root, XDG_CONFIG_HOME: resolve(root, "config"),
    XDG_DATA_HOME: resolve(root, "data"), XDG_STATE_HOME: resolve(root, "state"),
    XDG_CACHE_HOME: resolve(root, "cache"), TMUX: "", TMUX_PANE: "", TMUX_TMPDIR: resolve(root, "tmux"),
  };
  delete env.OPENCODE_CONFIG;
  delete env.OPENCODE_CONFIG_CONTENT;
  delete env.OPENCODE_DB;
  for (const path of [project, env.TMUX_TMPDIR, resolve(env.XDG_CONFIG_HOME, "opencode"), resolve(project, ".opencode")]) await mkdir(path, { recursive: true });

  provider = createServer((req, res) => {
    let body = "";
    req.on("data", (chunk) => { body += chunk; });
    req.on("end", () => {
      modelRequests.push(JSON.parse(body));
      res.writeHead(200, { "content-type": "text/event-stream" });
      res.end(`data: ${JSON.stringify({ id: "chatcmpl_fixture", object: "chat.completion.chunk", created: 1, model: "mock", choices: [{ index: 0, delta: { role: "assistant", content: "ok" }, finish_reason: "stop" }] })}\n\ndata: [DONE]\n\n`);
    });
  });
  await new Promise((r) => provider.listen(0, "127.0.0.1", r));

  const mcpServer = resolve(root, "mcp-fixture.mjs");
  await writeFile(mcpServer, MCP_FIXTURE);
  // Project registration: read-only scout profile, native tools, admin tool denied.
  await writeFile(resolve(project, ".opencode/opencode.json"), JSON.stringify({
    mcp: { servers: { "codebase-memory": { type: "local", command: [process.execPath, mcpServer], codemode: false } } },
    permissions: [{ action: "codebase-memory_admin_thing", resource: "*", effect: "deny" }],
  }));

  await writeFile(resolve(env.XDG_CONFIG_HOME, "opencode/opencode.json"), JSON.stringify({
    autoupdate: false,
    model: "fixture/mock", small_model: "fixture/mock",
    agents: {
      explorer: {
        description: "read-only explorer", mode: "subagent", model: "fixture/mock",
        permissions: [
          { action: "execute", resource: "*", effect: "deny" },
          { action: "shell", resource: "*", effect: "deny" },
          { action: "edit", resource: "*", effect: "deny" },
        ],
      },
    },
    provider: { fixture: {
      npm: "@ai-sdk/openai-compatible",
      options: { baseURL: `http://127.0.0.1:${provider.address().port}/v1`, apiKey: "fixture" },
      models: { mock: { name: "Mock", limit: { context: 16000, output: 1000 } } },
    } },
  }));

  await rm(resolve(env.XDG_CONFIG_HOME, "opencode/service.json"), { force: true });
  await execute(bin, ["service", "get", "password"], { env });
  await execute(bin, ["service", "set", "port", "49376"], { env });
  log = await open(resolve(root, "mcp-server.log"), "a");
  child = spawn(bin, ["serve", "--service", "--port", "49376"], { env, cwd: project, stdio: ["ignore", log.fd, log.fd] });
  const state = resolve(env.XDG_STATE_HOME, "opencode/service.json");
  let healthy = false;
  for (let i = 0; i < 120; i++) {
    try {
      const service = JSON.parse(await readFile(state, "utf8"));
      const auth = Buffer.from(`opencode:${service.password}`).toString("base64");
      const response = await fetch(`${service.url}/api/info`, { headers: { authorization: `Basic ${auth}` } });
      if (response.ok) { healthy = true; break; }
    } catch {}
    if (child.exitCode !== null) throw new Error(`Test server exited: ${await readFile(resolve(root, "mcp-server.log"), "utf8")}`);
    await new Promise((r) => setTimeout(r, 250));
  }
  assert.equal(healthy, true, "isolated v2 service became healthy");
  Object.assign(process.env, env);
  request = createRequest(bin);
  // Wait for the MCP catalog to connect before prompting, so a captured
  // request reflects a ready tool catalog rather than a startup race.
  for (let i = 0; i < 60; i++) {
    const mcp = (await request("/api/mcp", { query: { "location[directory]": project } })).data;
    if (mcp.some((s) => s.name === "codebase-memory" && s.status?.status === "connected")) break;
    await new Promise((r) => setTimeout(r, 100));
  }
}, { timeout: 60000 });

after(async () => {
  if (skip) return;
  if (env) await execute(bin, ["service", "stop"], { env, timeout: 15000 }).catch(() => {});
  child?.kill();
  await log?.close();
  if (provider) await new Promise((r) => provider.close(r));
});

test("native MCP read tool reaches an agent that denies Code Mode", { skip }, async () => {
  const session = (await request("/api/session", { method: "POST", body: {
    agent: "explorer", model: { providerID: "fixture", id: "mock" },
    title: "MCP native access", location: { directory: project },
  } })).data;
  await request(`/api/session/${session.id}/prompt`, { method: "POST", body: { text: "MCP access check" } });
  let outgoing;
  for (let i = 0; i < 100; i++) {
    outgoing = modelRequests.find((body) => body.tools?.length && body.messages.some((m) => m.role === "user" && m.content === "MCP access check"));
    if (outgoing) break;
    await new Promise((r) => setTimeout(r, 100));
  }
  assert.ok(outgoing, "captured the explorer request");
  const tools = outgoing.tools.map((tool) => tool.function.name);
  assert.ok(tools.includes("codebase-memory_read_thing"), `native MCP read tool is exposed: ${tools}`);
  assert.equal(tools.includes("execute"), false, "Code Mode stays denied for the explorer");
  assert.equal(tools.includes("codebase-memory_admin_thing"), false, "denied MCP tool is hidden");
});
