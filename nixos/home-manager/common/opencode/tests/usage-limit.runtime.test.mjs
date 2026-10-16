// Real v2 server test for the usage-limit plugin: a usage-limit 429 with a
// reset time must resume the same turn; a billing 429 must still fail.
// Everything (config, data, service registration) lives under
// OPENCODE_TEST_HOME, never the live installation.
import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, writeFile, readFile, open, rm, copyFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createServer } from "node:http";

const execute = promisify(execFile);
const root = process.env.OPENCODE_TEST_HOME;
const bin = process.env.OPENCODE_TEST_BIN;
const skip = (!root || !bin) && "Set OPENCODE_TEST_HOME and OPENCODE_TEST_BIN";
const pluginSource = fileURLToPath(new URL("../usage-limit.mjs", import.meta.url));
const project = skip ? "" : resolve(root, "project");
const PORT = 49377;
let child, log, env, provider, service;
const modelRequests = [];

const sse = (content) => {
  const chunk = (delta, finish_reason = null) => `data: ${JSON.stringify({
    id: "chatcmpl_fixture", object: "chat.completion.chunk", created: 1, model: "mock",
    choices: [{ index: 0, delta, finish_reason }],
  })}\n\n`;
  return chunk({ role: "assistant", content }) + chunk({}, "stop") + "data: [DONE]\n\n";
};

async function api(route, { method = "GET", body } = {}) {
  const response = await fetch(new URL(route, service.url), {
    method,
    headers: {
      "content-type": "application/json",
      authorization: `Basic ${Buffer.from(`opencode:${service.password}`).toString("base64")}`,
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}: ${(await response.text()).slice(0, 300)}`);
  return response.status === 204 ? undefined : response.json();
}

async function runTurn(text, timeoutMs = 60000) {
  const session = (await api("/api/session", { method: "POST", body: {
    model: { providerID: "fixture", id: "mock" }, title: text, location: { directory: project },
  } })).data;
  await api(`/api/session/${session.id}/prompt`, { method: "POST", body: { text } });
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const info = (await api(`/api/session/${session.id}`)).data;
    if (info.outcome) return info.outcome;
    await new Promise((r) => setTimeout(r, 200));
  }
  return "timeout";
}

before(async () => {
  if (skip) return;
  await rm(root, { recursive: true, force: true });
  env = {
    ...process.env, HOME: root, XDG_CONFIG_HOME: resolve(root, "config"),
    XDG_DATA_HOME: resolve(root, "data"), XDG_STATE_HOME: resolve(root, "state"),
    XDG_CACHE_HOME: resolve(root, "cache"), TMUX: "", TMUX_PANE: "", TMUX_TMPDIR: resolve(root, "tmux"),
    AGENT_STATE_OFF: "1", AGENT_CHECKPOINT: "0", OPENCODE_LIMIT_RESUME_MARGIN_MS: "300",
  };
  for (const key of ["OPENCODE_CONFIG", "OPENCODE_CONFIG_CONTENT", "OPENCODE_DB", "OPENCODE_LIMIT_RESUME"]) delete env[key];
  for (const path of [project, env.TMUX_TMPDIR, resolve(env.XDG_CONFIG_HOME, "opencode/plugins/usage-limit")]) {
    await mkdir(path, { recursive: true });
  }
  await copyFile(pluginSource, resolve(env.XDG_CONFIG_HOME, "opencode/plugins/usage-limit/index.js"));

  provider = createServer((req, res) => {
    let body = "";
    req.on("data", (chunk) => { body += chunk; });
    req.on("end", () => {
      const request = JSON.parse(body);
      modelRequests.push(request);
      const user = JSON.stringify(request.messages);
      const attempts = modelRequests.filter((r) => JSON.stringify(r.messages) === user).length;
      const limit = (error) => {
        res.writeHead(429, { "content-type": "application/json" });
        res.end(JSON.stringify({ error }));
      };
      if (user.includes("Billing check")) {
        return limit({ type: "insufficient_quota", message: "You exceeded your current quota, please check your plan and billing details.", resets_in_seconds: 1 });
      }
      if (user.includes("Limit check") && attempts === 1) {
        // ChatGPT-subscription style usage limit
        return limit({ type: "usage_limit_reached", message: "You have hit your usage limit.", resets_in_seconds: 1 });
      }
      res.writeHead(200, { "content-type": "text/event-stream" });
      res.end(sse("Resumed fixture"));
    });
  });
  await new Promise((r) => provider.listen(0, "127.0.0.1", r));

  await writeFile(resolve(env.XDG_CONFIG_HOME, "opencode/opencode.json"), JSON.stringify({
    autoupdate: false,
    model: "fixture/mock", small_model: "fixture/mock",
    provider: { fixture: {
      npm: "@ai-sdk/openai-compatible",
      options: { baseURL: `http://127.0.0.1:${provider.address().port}/v1`, apiKey: "fixture" },
      models: { mock: { name: "Mock", limit: { context: 16000, output: 1000 } } },
    } },
  }));
  await execute(bin, ["service", "get", "password"], { env });
  await execute(bin, ["service", "set", "port", String(PORT)], { env });
  log = await open(resolve(root, "server.log"), "a");
  child = spawn(bin, ["serve", "--service", "--port", String(PORT)], { env, cwd: project, stdio: ["ignore", log.fd, log.fd] });
  for (let i = 0; i < 120; i++) {
    try {
      service = JSON.parse(await readFile(resolve(env.XDG_STATE_HOME, "opencode/service.json"), "utf8"));
      const plugins = (await api(`/api/plugin?location[directory]=${encodeURIComponent(project)}`)).data;
      if (plugins.some((p) => p.id === "usage-limit" && p.state.status === "active")) break;
    } catch {}
    if (child.exitCode !== null) throw new Error(`server exited: ${await readFile(resolve(root, "server.log"), "utf8")}`);
    await new Promise((r) => setTimeout(r, 250));
  }
}, { timeout: 60000 });

after(async () => {
  if (skip) return;
  await execute(bin, ["service", "stop"], { env, timeout: 15000 }).catch(() => {});
  child?.kill();
  await log?.close();
  if (provider) await new Promise((r) => provider.close(r));
});

test("the usage-limit plugin is active in a real v2 service", { skip }, async () => {
  const plugins = (await api(`/api/plugin?location[directory]=${encodeURIComponent(project)}`)).data;
  const plugin = plugins.find((p) => p.id === "usage-limit");
  assert.equal(plugin?.state.status, "active", JSON.stringify(plugins.map((p) => [p.id, p.state])));
});

test("a usage limit with a reset time resumes the same turn after the reset", { skip, timeout: 90000 }, async () => {
  const before = modelRequests.length;
  assert.equal(await runTurn("Limit check"), "succeeded");
  assert.equal(modelRequests.length - before, 2, "one failed request, one retried request");
  const logText = await readFile(resolve(root, "server.log"), "utf8");
  assert.match(logText, /\[usage-limit\] .*provider\.quota, resuming at/);
});

test("a billing quota error still fails the turn", { skip, timeout: 90000 }, async () => {
  assert.equal(await runTurn("Billing check"), "failed");
});
