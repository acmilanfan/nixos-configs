import assert from "node:assert/strict";
import test from "node:test";
import { pathToFileURL } from "node:url";

const pluginURL = process.env.OPENCODE_TEST_RESEARCH_CONTEXT
  ? pathToFileURL(process.env.OPENCODE_TEST_RESEARCH_CONTEXT)
  : new URL("../research-context/index.js", import.meta.url);

async function contextHook() {
  let callback;
  const plugin = (await import(pluginURL.href)).default;
  await plugin.setup({ session: { hook: async (kind, hook) => {
    assert.equal(kind, "context");
    callback = hook;
  } } });
  return callback;
}

const memory = { type: "text", text: "<memory_instructions>\nMemory policy\n</memory_instructions>\n<memory_blocks>private notes</memory_blocks>" };

test("research omits injected memory while preserving its prompt and conversation", async () => {
  const hook = await contextHook();
  const prompt = { type: "text", text: "You are a research assistant." };
  const messages = [{ role: "user", content: [{ type: "text", text: "Explain <memory_instructions> tags" }] }];
  const event = { agent: "research", system: [prompt, memory], messages };
  await hook(event);
  assert.deepEqual(event.system, [prompt]);
  assert.deepEqual(event.messages, messages);
});

test("other agents retain their exact memory and instruction blocks", async () => {
  const hook = await contextHook();
  for (const agent of ["build", "local", "general"]) {
    const system = [{ type: "text", text: "Coding instructions" }, structuredClone(memory)];
    const event = { agent, system };
    await hook(event);
    assert.equal(event.system, system);
    assert.deepEqual(event.system[1], memory);
  }
});

test("research keeps ordinary instructions that merely mention memory markup", async () => {
  const hook = await contextHook();
  const system = [{ type: "text", text: "Instructions: <memory_instructions> is an XML tag." }];
  const event = { agent: "research", system };
  await hook(event);
  assert.deepEqual(event.system, system);
});
