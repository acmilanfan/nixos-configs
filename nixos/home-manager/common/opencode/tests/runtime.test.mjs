// Real v2 server smoke tests, with all config/data/logs isolated in artifacts.
import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, writeFile, readFile, open, rm, symlink } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createServer } from "node:http";
import { createRequest, createStorage } from "../vicinae-storage.mjs";

const execute = promisify(execFile);
const root = process.env.OPENCODE_TEST_HOME;
const bin = process.env.OPENCODE_TEST_BIN;
const pluginPackage = process.env.OPENCODE_TEST_PLUGIN_DIR;
const memoryPlugin = process.env.OPENCODE_TEST_MEMORY_PLUGIN;
// Integration suite: skip (not fail) without a prepared test environment.
const skip = (!root || !bin || !pluginPackage) && "Set OPENCODE_TEST_HOME, OPENCODE_TEST_BIN, and OPENCODE_TEST_PLUGIN_DIR (built directory plugin)";
const plugins = fileURLToPath(new URL("..", import.meta.url));
const project = skip ? "" : resolve(root, "project");
let child, log, request, storage, env, provider;
const modelRequests = [];

before(async () => {
  if (skip) return;
  env = {
    ...process.env, HOME: root, XDG_CONFIG_HOME: resolve(root, "config"),
    XDG_DATA_HOME: resolve(root, "data"), XDG_STATE_HOME: resolve(root, "state"),
    XDG_CACHE_HOME: resolve(root, "cache"), TMUX: "", TMUX_PANE: "", TMUX_TMPDIR: resolve(root, "tmux"),
    GIT_AUTHOR_NAME: "OpenCode test", GIT_AUTHOR_EMAIL: "test@example.invalid",
    GIT_COMMITTER_NAME: "OpenCode test", GIT_COMMITTER_EMAIL: "test@example.invalid",
  };
  delete env.OPENCODE_CONFIG;
  delete env.OPENCODE_CONFIG_CONTENT;
  delete env.OPENCODE_DB;
  for (const path of [project, env.TMUX_TMPDIR, resolve(env.XDG_CONFIG_HOME, "opencode")]) await mkdir(path, { recursive: true });
  await execute("git", ["init", "-q", project], { env });
  await writeFile(resolve(project, "fixture.txt"), "before\n");
  await execute("git", ["add", "fixture.txt"], { cwd: project, env });
  provider = createServer((req, res) => {
    if (req.method === "GET" && req.url === "/page") {
      res.writeHead(200, { "content-type": "text/plain" });
      res.end("Research fixture source");
      return;
    }
    let body = "";
    req.on("data", (chunk) => { body += chunk; });
    req.on("end", () => {
      const requestBody = JSON.parse(body);
      modelRequests.push(requestBody);
      res.writeHead(200, { "content-type": "text/event-stream" });
      const chunk = (delta, finish_reason = null) => `data: ${JSON.stringify({
        id: "chatcmpl_fixture", object: "chat.completion.chunk", created: 1, model: "mock",
        choices: [{ index: 0, delta, finish_reason }],
      })}\n\n`;
      const hybridTask = requestBody.messages.find((m) => m.role === "user"
        && typeof m.content === "string" && m.content.startsWith("Hybrid routing "));
      if (hybridTask && !requestBody.messages.some((m) => m.role === "tool")) {
        const agent = hybridTask.content.slice("Hybrid routing ".length);
        res.end(chunk({ role: "assistant", tool_calls: [{ index: 0, id: "call_hybrid_child", type: "function",
          function: { name: "subagent", arguments: JSON.stringify({ agent,
            description: "Check hybrid worker routing", prompt: `Hybrid child ${agent}: report the fixture text.` }) },
        }] }) + chunk({}, "tool_calls") + "data: [DONE]\n\n");
      } else if (requestBody.tools?.some((tool) => tool.function.name === "webfetch")
          && requestBody.messages.some((m) => m.role === "user" && m.content.startsWith("Profile check research"))
          && !requestBody.messages.some((m) => m.role === "tool")) {
        res.end(chunk({ role: "assistant", tool_calls: [{ index: 0, id: "call_research_page", type: "function",
          function: { name: "webfetch", arguments: JSON.stringify({ url: `http://127.0.0.1:${provider.address().port}/page`, format: "text" }) },
        }] }) + chunk({}, "tool_calls") + "data: [DONE]\n\n");
      } else {
        res.end(chunk({ role: "assistant", content: "Migration fixture needle" }) + chunk({}, "stop") + "data: [DONE]\n\n");
      }
    });
  });
  await new Promise((r) => provider.listen(0, "127.0.0.1", r));
  const pluginDirectory = resolve(env.XDG_CONFIG_HOME, "opencode/plugins");
  await mkdir(pluginDirectory, { recursive: true });
  await rm(resolve(pluginDirectory, "agent-state"), { recursive: true, force: true });
  // Exercise Home Manager's actual whole-directory symlink, not copies. The
  // v2 loader checks real entrypoint containment inside the resolved root.
  await symlink(pluginPackage, resolve(pluginDirectory, "agent-state"), "dir");
  await writeFile(resolve(pluginDirectory, "tmux-session.js"), await readFile(resolve(plugins, "tmux-session.mjs")));
  const configModule = fileURLToPath(new URL("../../opencode.nix", import.meta.url));
  const evaluated = await execute("nix-instantiate", ["--eval", "--strict", "--json", "--expr", `
    let m = import ${configModule} {
      config.home.username = "gentooway"; secrets = {}; unstable = {}; inputs = {};
      pkgs = { mcp-nixos = "/fixture/mcp-nixos"; jq = "/fixture/jq";
        opencode-agent-memory = "/fixture/memory"; stdenv.isDarwin = true;
        runCommand = name: env: script: "/fixture/" + name; };
      lib.hm.dag.entryAfter = _: value: value;
    }; in m.home.activation.opencodeSettings
  `]);
  const activation = JSON.parse(evaluated.stdout);
  const settings = JSON.parse(activation.split("cat <<'EOF'\n")[1].split("\nEOF")[0]);
  const contextPlugins = [];
  if (memoryPlugin) {
    // Real pinned memory implementation, then the exact configured filter.
    const memoryDirectory = resolve(root, "memory-plugin");
    await mkdir(memoryDirectory, { recursive: true });
    await writeFile(resolve(memoryDirectory, "index.js"), `export { default } from ${JSON.stringify(new URL("dist/index.js", pathToFileURL(memoryPlugin + "/")).href)};\n`);
    const sources = new Map([
      ["opencode-agent-memory@0.3.0", memoryDirectory],
      ["/fixture/opencode-research-context-plugin", resolve(plugins, "research-context")],
    ]);
    // Preserve Nix's evaluated ordering, not a parallel hand-written list.
    for (const target of settings.plugins) {
      assert.ok(sources.has(target), `provide a real fixture for configured plugin ${target}`);
      contextPlugins.push(sources.get(target));
    }
  }
  await writeFile(resolve(env.XDG_CONFIG_HOME, "opencode/opencode.json"), JSON.stringify({
    autoupdate: false,
    agents: settings.agents,
    commands: settings.commands,
    plugins: contextPlugins,
    model: "fixture/mock", small_model: "fixture/mock",
    providers: { fixture: {
      package: "@opencode/ai/providers/openai-compatible",
      settings: { baseURL: `http://127.0.0.1:${provider.address().port}/v1`, apiKey: "fixture" },
      models: { mock: { name: "Mock", limit: { context: 16000, output: 1000 } } },
    }, openai: {
      package: "@opencode/ai/providers/openai-compatible",
      settings: { baseURL: `http://127.0.0.1:${provider.address().port}/v1`, apiKey: "fixture" },
      models: { "gpt-6.1-sol": { name: "Lead fixture", limit: { context: 16000, output: 1000 } } },
    }, "opencode-go": {
      // Redirect the real configured worker model to the local fixture. This
      // verifies selection without credentials, paid calls, or live providers.
      package: "@opencode/ai/providers/openai-compatible",
      settings: { baseURL: `http://127.0.0.1:${provider.address().port}/v1`, apiKey: "fixture" },
      models: { "deepseek-v4.1-flash": {
        name: "Flash fixture", limit: { context: 16000, output: 1000 },
        // The built-in catalog model has its own endpoint, which overrides
        // provider-level settings. Pin the model route too: never call Go.
        package: "@opencode/ai/providers/openai-compatible",
        settings: { baseURL: `http://127.0.0.1:${provider.address().port}/v1`, apiKey: "fixture" },
        variants: [
          { id: "low", settings: { reasoningEffort: "low" } },
          { id: "max", settings: { reasoningEffort: "max" } },
        ],
      } },
    } },
  }));
  // Mirror the ordered Nix activation: initialize once before either process
  // can generate a credential, including on an initially empty installation.
  await rm(resolve(env.XDG_CONFIG_HOME, "opencode/service.json"), { force: true });
  await execute(bin, ["service", "get", "password"], { env });
  await execute(bin, ["service", "set", "port", "49375"], { env });
  log = await open(resolve(root, "server.log"), "a");
  child = spawn(bin, ["serve", "--service", "--port", "49375"], { env, cwd: project, stdio: ["ignore", log.fd, log.fd] });
  const state = resolve(env.XDG_STATE_HOME, "opencode/service.json");
  let healthy = false;
  for (let i = 0; i < 120; i++) {
    try {
      const service = JSON.parse(await readFile(state, "utf8"));
      const auth = Buffer.from(`opencode:${service.password}`).toString("base64");
      const response = await fetch(`${service.url}/api/info`, { headers: { authorization: `Basic ${auth}` } });
      if (response.ok) { healthy = true; break; }
    } catch {}
    if (child.exitCode !== null) throw new Error(`Test server exited: ${await readFile(resolve(root, "server.log"), "utf8")}`);
    await new Promise((r) => setTimeout(r, 250));
  }
  assert.equal(healthy, true, "isolated v2 service became healthy");
  // The transport reads only these XDG paths; its official CLI bootstrap also
  // inherits this environment and cannot touch the live OpenCode service.
  Object.assign(process.env, env);
  request = createRequest(bin);
  storage = createStorage(request, async () => []);
  const catalog = (await request("/api/model", { query: { "location[directory]": project } })).data;
  const flash = catalog.find((model) => model.providerID === "opencode-go" && model.id === "deepseek-v4.1-flash");
  assert.ok(flash, "configured Flash fixture is available");
  assert.equal(flash.settings?.baseURL, `http://127.0.0.1:${provider.address().port}/v1`,
    "Flash's model-specific route must remain local before any subagent runs");
}, { timeout: 60000 });

after(async () => {
  if (skip) return;
  if (env) await execute("tmux", ["kill-server"], { env }).catch(() => {});
  if (env) await execute(bin, ["service", "stop"], { env, timeout: 15000 }).catch(() => {});
  child?.kill();
  await log?.close();
  if (provider) await new Promise((r) => provider.close(r));
});

test("real service accepts the migrated server plugin entrypoints", { skip }, async () => {
  assert.equal(await storage.checkDatabase(), null);
  let result;
  for (let i = 0; i < 40; i++) {
    result = await request("/api/plugin", { query: { "location[directory]": project } });
    if (result.data.some((p) => p.id === "agent-state" && p.state.status === "active")) break;
    await new Promise((r) => setTimeout(r, 100));
  }
  const ids = result.data.map((p) => p.id);
  assert.ok(ids.includes("agent-state"), JSON.stringify(ids));
  assert.ok(ids.includes("tmux-session"), JSON.stringify(ids));
  assert.equal(result.data.find((p) => p.id === "agent-state").features.tui, true);
});

test("initialized credentials are shared by concurrently starting clients and the registered server", { skip }, async () => {
  const clients = await Promise.all([1, 2].map(() => execute(bin, ["service", "get", "password"], { env })));
  const service = JSON.parse(await readFile(resolve(env.XDG_STATE_HOME, "opencode/service.json"), "utf8"));
  // Do not print credentials in an assertion failure.
  assert.ok(clients.every((client) => client.stdout.trim() === service.password));
});

test("Build excludes hybrid children but retains standard subagent delegation", { skip }, async () => {
  for (const agent of ["hybrid-explore", "hybrid-review", "hybrid-worker", "general", "explore"]) {
    const denied = agent.startsWith("hybrid-");
    const session = (await request("/api/session", { method: "POST", body: {
      agent: "build", model: { providerID: "fixture", id: "mock" },
      title: `Build routing ${agent}`, location: { directory: project },
    } })).data;
    const start = modelRequests.length;
    // Deliberately force a call even when the child is absent from the catalog:
    // removing discoverability alone must not be mistaken for enforcement.
    await request(`/api/session/${session.id}/prompt`, { method: "POST", body: { text: `Hybrid routing ${agent}` } });
    let transcript = [];
    for (let i = 0; i < 150; i++) {
      transcript = await storage.loadTranscript(session.id);
      if (transcript.some((e) => e.parts.some((p) => p.type === "tool" && p.tool === "subagent"
        && ["completed", "error"].includes(p.state.status)))) break;
      await new Promise((r) => setTimeout(r, 100));
    }
    const outgoing = modelRequests.slice(start).find((body) => body.messages.some((m) => m.role === "user"
      && m.content === `Hybrid routing ${agent}`));
    assert.ok(outgoing, "captured Build's model request");
    assert.equal(outgoing.model, "mock", "Build keeps the session's selected model");
    const subagent = outgoing.tools.find((tool) => tool.function.name === "subagent");
    assert.ok(subagent, "Build retains its standard subagent tool");
    for (const id of ["hybrid-explore", "hybrid-review", "hybrid-worker"]) {
      assert.equal(JSON.stringify(subagent).includes(id), false, `${id} is absent from Build's child catalog`);
    }
    const call = transcript.flatMap((e) => e.parts).find((p) => p.tool === "subagent");
    assert.equal(call?.state.status, denied ? "error" : "completed", JSON.stringify(call));
    const children = (await request("/api/session", { query: { parentID: session.id } })).data;
    assert.equal(children.length, denied ? 0 : 1, `${agent}: denied calls create no child; standard calls still run`);
    if (!denied) {
      assert.equal(children[0].agent, agent);
      assert.equal(children[0].model.providerID, "fixture", "standard children still inherit Build's selected model");
      assert.equal(children[0].model.id, "mock");
    }
    let finished = false;
    for (let i = 0; i < 100; i++) {
      const { stdout } = await execute("git", ["log", "--format=%(trailers:key=Agent-Event,valueonly)",
        `refs/worktree/agent/${session.id}`], { cwd: project, env }).catch(() => ({ stdout: "" }));
      if (stdout.includes("post")) { finished = true; break; }
      await new Promise((r) => setTimeout(r, 50));
    }
    assert.ok(finished, `${agent} Build turn finished`);
    await storage.deleteSession({ id: session.id });
  }
});

test("hybrid command selects Sol and delegates to Flash workers without inheriting its lead model", { skip }, async () => {
  let agents = [];
  for (let i = 0; i < 40; i++) {
    agents = (await request("/api/agent", { query: { "location[directory]": project } })).data;
    // Builtins appear before asynchronously discovered user configuration.
    if (agents.some((agent) => agent.id === "local")) break;
    await new Promise((r) => setTimeout(r, 100));
  }
  assert.ok(agents.some((agent) => agent.id === "hybrid"), `Nix registers the hybrid primary agent: ${agents.map((agent) => agent.id)}`);
  for (const [agent, variant] of [["hybrid-review", "max"], ["hybrid-explore", "low"], ["hybrid-worker", "max"]]) {
    const profile = agents.find((entry) => entry.id === agent);
    assert.ok(profile, `Nix registers ${agent}`);
    assert.equal(profile.steps, undefined, `${agent} has no step cap`);
    const session = (await request("/api/session", { method: "POST", body: {
      agent: "build", model: { providerID: "fixture", id: "mock" },
      title: `Routing ${agent}`, location: { directory: project },
    } })).data;
    const start = modelRequests.length;
    await request(`/api/session/${session.id}/command`, { method: "POST", body: { name: "hybrid", text: `Hybrid routing ${agent}` } });
    let transcript = [];
    for (let i = 0; i < 150; i++) {
      transcript = await storage.loadTranscript(session.id);
      if (transcript.some((e) => e.parts.some((p) => p.type === "tool" && p.tool === "subagent"
        && ["completed", "error"].includes(p.state.status)))) break;
      await new Promise((r) => setTimeout(r, 100));
    }
    const call = transcript.flatMap((e) => e.parts).find((p) => p.tool === "subagent");
    assert.equal(call?.state.status, "completed", JSON.stringify(call));
    const assistant = transcript.find((e) => e.message.role === "assistant" && e.message.agent);
    assert.equal(assistant?.message.agent, "hybrid", "command changes the previously selected session agent");
    const lead = modelRequests.slice(start).find((body) => body.messages.some((m) => m.role === "user"
      && m.content === `Hybrid routing ${agent}`));
    assert.ok(lead, "captured the lead's command request");
    assert.equal(lead.model, "gpt-6.1-sol", "command changes the previously selected session model");
    const child = modelRequests.slice(start).find((body) => body.messages.some((m) => m.role === "user"
      && typeof m.content === "string" && m.content.endsWith(`Hybrid child ${agent}: report the fixture text.`)));
    assert.ok(child, `captured ${agent} request through real subagent execution`);
    assert.equal(child.model, "deepseek-v4.1-flash");
    const children = (await request("/api/session", { query: { parentID: session.id } })).data;
    assert.equal(children.length, 1, "one actual child was created");
    assert.equal(children[0].agent, agent);
    assert.equal(children[0].model.providerID, "opencode-go");
    assert.equal(children[0].model.id, "deepseek-v4.1-flash");
    assert.equal(children[0].model.variant, variant, `${agent} retains its own effort, not the lead's high`);
    const tools = child.tools.map((tool) => tool.function.name);
    assert.equal(tools.includes("subagent"), false, "workers cannot recursively delegate");
    assert.equal(tools.includes("question"), false, "workers report blockers to their lead");
    if (agent !== "hybrid-worker") {
      for (const name of ["patch", "edit", "write", "shell", "execute", "skill"]) assert.equal(tools.includes(name), false, `${agent} cannot use ${name}`);
      assert.ok(tools.includes("read"));
      assert.ok(tools.includes("grep"));
    } else {
      assert.ok(tools.some((name) => ["patch", "edit", "write"].includes(name)), `worker has editing tools: ${tools}`);
      assert.ok(tools.includes("shell"));
    }
    // Wait for the parent's final answer/checkpoint before deleting its session.
    let finished = false;
    for (let i = 0; i < 100; i++) {
      const { stdout } = await execute("git", ["log", "--format=%(trailers:key=Agent-Event,valueonly)",
        `refs/worktree/agent/${session.id}`], { cwd: project, env }).catch(() => ({ stdout: "" }));
      if (stdout.includes("post")) { finished = true; break; }
      await new Promise((r) => setTimeout(r, 50));
    }
    assert.ok(finished, `${agent} lead finished`);
    await storage.deleteSession({ id: session.id });
  }
});

test("Nix research profile sends only web tools and no memory while local/build retain it", { skip: skip || (!memoryPlugin && "Set OPENCODE_TEST_MEMORY_PLUGIN") }, async () => {
  for (const agent of ["build", "local", "research"]) {
    const session = (await request("/api/session", { method: "POST", body: {
      agent, model: { providerID: "fixture", id: "mock" },
      title: `Profile ${agent}`, location: { directory: project },
    } })).data;
    const text = `Profile check ${agent}`;
    await request(`/api/session/${session.id}/prompt`, { method: "POST", body: { text } });
    let outgoing;
    for (let i = 0; i < 100; i++) {
      outgoing = modelRequests.find((body) => body.tools?.length && body.messages.some((m) => m.role === "user" && m.content === text));
      if (outgoing) break;
      await new Promise((r) => setTimeout(r, 100));
    }
    assert.ok(outgoing, `captured ${agent} request`);
    const prompt = JSON.stringify(outgoing.messages);
    assert.equal(prompt.includes("<memory_blocks>"), agent !== "research");
    const tools = outgoing.tools.map((tool) => tool.function.name).sort();
    if (agent === "research") {
      assert.deepEqual(tools, ["webfetch", "websearch"]);
      assert.equal(prompt.includes("# Code Mode"), false);
      assert.equal(prompt.includes("<available_skills>"), false);
      assert.match(prompt, /conversational research assistant/);
    } else {
      assert.ok(tools.includes("execute"));
      assert.ok(prompt.includes("memory_get"));
    }
    // Do not leave headless sessions for the delayed tmux opener to resurrect
    // when the following TUI test starts its isolated tmux server.
    // A completed assistant message may only be an intermediate tool call.
    // Wait for the execution's async checkpoint subscriber before deleting it.
    let finished = false;
    for (let i = 0; i < 100; i++) {
      const { stdout } = await execute("git", ["log", "--format=%(trailers:key=Agent-Event,valueonly)",
        `refs/worktree/agent/${session.id}`], { cwd: project, env }).catch(() => ({ stdout: "" }));
      if (stdout.includes("post")) { finished = true; break; }
      await new Promise((r) => setTimeout(r, 50));
    }
    assert.ok(finished, `${agent} execution and post-checkpoint completed`);
    if (agent === "research") {
      assert.ok(modelRequests.some((body) => body.messages.some((m) => m.role === "tool"
        && typeof m.content === "string" && m.content.includes("Research fixture source"))),
      "research can execute webfetch and receive the page without a permission prompt");
    }
    await storage.deleteSession({ id: session.id });
  }
});

test("session browser creates, reads, searches and deletes real v2 sessions", { skip }, async () => {
  const created = await request("/api/session", { method: "POST", body: {
    title: "V2 smoke unique", location: { directory: project },
  } });
  const session = created.data;
  assert.ok(session.id);
  await request(`/api/session/${session.id}/prompt`, { method: "POST", body: { text: "Return the fixture text" } });
  let transcript = [];
  for (let i = 0; i < 100; i++) {
    transcript = await storage.loadTranscript(session.id);
    if (transcript.some((e) => e.message.role === "assistant" && e.message.time.completed)) break;
    await new Promise((r) => setTimeout(r, 200));
  }
  assert.ok((await storage.loadSessions()).some((s) => s.id === session.id && s.directory === project));
  assert.ok(transcript.some((e) => e.parts.some((p) => p.text === "Migration fixture needle")), JSON.stringify(transcript));
  assert.ok((await storage.searchSessions("fixture needle")).some((s) => s.id === session.id));
  const projectInfo = (await storage.loadProjects()).find((p) => p.id === session.projectID);
  assert.ok(projectInfo);
  assert.equal(typeof projectInfo.worktree.split("/").at(-1), "string");
  await request(`/api/session/${session.id}/shell`, { method: "POST", body: { command: "printf 'shell fixture output'" } });
  let shell = "";
  for (let i = 0; i < 30; i++) {
    shell = (await storage.loadTranscript(session.id)).flatMap((e) => e.parts.map((p) => p.text || "")).join("\n");
    if (shell.includes("[exited; exit 0]\nshell fixture output")) break;
    await new Promise((r) => setTimeout(r, 100));
  }
  assert.ok(shell.includes("$ printf 'shell fixture output'\n[exited; exit 0]\nshell fixture output"));
  assert.deepEqual(await storage.getOpenSessions(), []);
  // The real context hook + event subscription must create pre/post git refs.
  let checkpoints = "";
  for (let i = 0; i < 20; i++) {
    checkpoints = (await execute("git", ["log", "--format=%(trailers:key=Agent-Event,valueonly)", `refs/worktree/agent/${session.id}`], { cwd: project, env }).catch(() => ({ stdout: "" }))).stdout;
    if (checkpoints.includes("post")) break;
    await new Promise((r) => setTimeout(r, 200));
  }
  assert.ok(checkpoints.includes("pre") && checkpoints.includes("post"), checkpoints);
  await storage.deleteSession({ id: session.id });
  assert.equal((await storage.loadSessions()).some((s) => s.id === session.id), false);
});

test("the real TUI pins its session and reports state to its own tmux pane without duplicate windows", { skip }, async () => {
  const created = await request("/api/session", { method: "POST", body: {
    title: "Pane smoke", location: { directory: project },
  } });
  const id = created.data.id;
  const { stdout } = await execute("tmux", ["new-session", "-d", "-P", "-F", "#{pane_id}",
    "-s", "opencode-v2-smoke", "-c", project, `${bin} --session ${id}`], { env });
  const pane = stdout.trim();
  let marker = "";
  for (let i = 0; i < 60; i++) {
    marker = (await execute("tmux", ["show-options", "-p", "-v", "-t", pane, "@opencode-session"], { env }).catch(() => ({ stdout: "" }))).stdout.trim();
    if (marker === id) break;
    await new Promise((r) => setTimeout(r, 100));
  }
  const screen = (await execute("tmux", ["capture-pane", "-p", "-t", pane], { env })).stdout;
  assert.equal(marker, id, screen);
  let state = "";
  for (let i = 0; i < 30; i++) {
    state = (await execute("tmux", ["show-environment", "-g", `TMUX_AGENT_PANE_${pane}_STATE`], { env }).catch(() => ({ stdout: "" }))).stdout;
    if (state.includes("=done")) break;
    await new Promise((r) => setTimeout(r, 100));
  }
  assert.match(state, /=done/);
  const script = fileURLToPath(new URL("../../scripts/ai-agent-list", import.meta.url));
  const detected = (await execute("bash", [script], { env })).stdout;
  assert.match(detected, /\|done\|OpenCode\|project\|/);
  // The delayed headless-session opener must see the TUI marker and skip it.
  await new Promise((r) => setTimeout(r, 1700));
  const windows = (await execute("tmux", ["list-windows", "-t", "opencode-v2-smoke", "-F", "#{window_id}"], { env })).stdout.trim().split("\n");
  assert.equal(windows.length, 1);
  await execute("tmux", ["kill-server"], { env });
  await storage.deleteSession({ id });
});
