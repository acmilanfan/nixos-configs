import assert from "node:assert/strict";
import test from "node:test";
import { existsSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const upstream = resolve(homedir(), ".cache/opencode-superpowers/.opencode/plugins/superpowers.js");
const available = existsSync(upstream);
const pluginURL = process.env.OPENCODE_TEST_SUPERPOWERS_PLUGIN
  ? pathToFileURL(process.env.OPENCODE_TEST_SUPERPOWERS_PLUGIN)
  : new URL("../superpowers.mjs", import.meta.url);

// Exercise the real upstream plugin, not a fabricated bootstrap. Its cache is
// installed by Home Manager; machines without it can still run other tests.
async function contextHook({ child = false } = {}) {
  const hooks = new Map();
  const skills = [];
  const ctx = {
    skill: { transform: async (update) => update({ add: (skill) => skills.push(skill) }) },
    session: {
      get: async ({ sessionID }) => ({ id: sessionID, ...(child ? { parentID: "ses_parent" } : {}) }),
      hook: async (kind, callback) => { hooks.set(kind, callback); },
    },
  };
  const plugin = (await import(pluginURL.href)).default;
  await plugin.setup(ctx);
  assert.ok(skills.some((skill) => skill.id === "using-superpowers"), "upstream skills remain registered");
  return hooks.get("context");
}

function event(agentID, sessionID, messages = [{ role: "user", content: [{ type: "text", text: "test" }] }]) {
  // V2's context hook carries the agent ID, not an Agent.Info object.
  return { agent: agentID, sessionID, system: [], messages };
}

test("local requests keep user content without injecting unavailable skill instructions", { skip: !available }, async () => {
  const hook = await contextHook();
  for (const messages of [
    [{ role: "user", content: [{ type: "text", text: "test" }] }],
    [{ role: "assistant", content: [{ type: "text", text: "checkpoint" }] }],
  ]) {
    const request = event("local", "ses_local_regression", structuredClone(messages));
    await hook(request);
    await hook(request);
    assert.deepEqual(request.messages, messages);
  }
});

test("build retains the upstream bootstrap without duplicating it across steps", { skip: !available }, async () => {
  const hook = await contextHook();
  const request = event("build", "ses_build_regression");
  await hook(request);
  await hook(request);
  assert.equal(request.messages[0].content.length, 2);
  assert.match(request.messages[0].content[0].text, /You have superpowers/);
  assert.equal(request.messages[0].content[1].text, "test");
});

test("research requests do not receive the coding controller bootstrap", { skip: !available }, async () => {
  const hook = await contextHook();
  const request = event("research", "ses_research_regression");
  await hook(request);
  assert.deepEqual(request.messages[0].content, [{ type: "text", text: "test" }]);
});

test("child sessions still skip controller instructions", { skip: !available }, async () => {
  const hook = await contextHook({ child: true });
  const request = event("general", "ses_child_regression");
  await hook(request);
  assert.deepEqual(request.messages[0].content, [{ type: "text", text: "test" }]);
});

test("V1 named and server entrypoints retain upstream skill registration and bootstrap", { skip: !available }, async () => {
  const module = await import(pluginURL.href);
  for (const entrypoint of [module.SuperpowersPlugin, module.default.server]) {
    const hooks = await entrypoint({
      client: { session: { get: async ({ path: { id } }) => ({ data: { id } }) } },
      directory: "/work/repo",
    });
    const config = {};
    await hooks.config(config);
    // The cache path is a symlink to the pinned checkout; upstream registers
    // the skills dir from its real location, so compare real paths.
    const skills = realpathSync(resolve(homedir(), ".cache/opencode-superpowers/skills"));
    assert.ok(config.skills.paths.some((p) => existsSync(p) && realpathSync(p) === skills));
    const output = { messages: [{ info: { role: "user", sessionID: "ses_v1_regression" },
      parts: [{ type: "text", text: "test" }] }] };
    await hooks["experimental.chat.messages.transform"]({}, output);
    await hooks["experimental.chat.messages.transform"]({}, output);
    assert.equal(output.messages[0].parts.length, 2);
    assert.match(output.messages[0].parts[0].text, /You have superpowers/);
    assert.equal(output.messages[0].parts[1].text, "test");
  }
});

test("V1-shaped setup still returns without registering V2 hooks", { skip: !available }, async () => {
  const plugin = (await import(pluginURL.href)).default;
  assert.equal(await plugin.setup({ client: {}, directory: "/work/repo" }), undefined);
});
