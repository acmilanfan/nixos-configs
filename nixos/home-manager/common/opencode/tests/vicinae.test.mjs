import assert from "node:assert/strict";
import test from "node:test";

const adapter = () => import("../vicinae-storage.mjs");
const session = (id, title, extra = {}) => ({
  id, title, slug: id, version: "2.0.27", projectID: "project_one",
  location: { directory: "/work/repo" }, time: { created: 1, updated: 2 }, ...extra,
});

test("sessions follow opaque cursors without repeating order and exclude children", async () => {
  const { createStorage } = await adapter();
  const calls = [];
  const storage = createStorage(async (route, options) => {
    calls.push(options.query);
    if (!options.query.cursor) return { data: [session("ses_one", "One")], cursor: { next: "opaque cursor" } };
    return { data: [session("ses_two", "Two"), session("ses_child", "Child", { parentID: "ses_one" })], cursor: {} };
  });
  const rows = await storage.loadSessions();
  assert.deepEqual(rows.map((s) => [s.id, s.directory]), [["ses_one", "/work/repo"], ["ses_two", "/work/repo"]]);
  assert.deepEqual(calls, [{ limit: 200, order: "desc" }, { limit: 200, cursor: "opaque cursor" }]);
});

test("v2 assistant tool results and model references remain visible in transcripts", async () => {
  const { transcriptEntry } = await adapter();
  const result = transcriptEntry({
    id: "msg_one", type: "assistant", time: { created: 10, completed: 20 },
    model: { id: "qwen", providerID: "omlx" }, agent: "build", cost: 0,
    content: [
      { type: "text", text: "Fixed it." },
      { type: "tool", id: "call_one", name: "shell", state: {
        status: "completed", input: { command: "pwd" }, content: [{ type: "text", text: "/work/repo" }],
      } },
    ],
  }, "ses_one");
  assert.equal(result.message.role, "assistant");
  assert.equal(result.message.modelID, "qwen");
  assert.equal(result.message.providerID, "omlx");
  assert.equal(result.parts[0].text, "Fixed it.");
  assert.deepEqual(result.parts[1].state, { status: "completed", input: { command: "pwd" }, output: "/work/repo" });
  assert.equal(result.parts[1].tool, "shell");
});

test("messages paginate oldest first and retain user prompts and compaction summaries", async () => {
  const { createStorage } = await adapter();
  const storage = createStorage(async (_route, options) => options.query.cursor
    ? { data: [{ id: "msg_two", type: "compaction", summary: "Earlier decisions", time: { created: 2 } }], cursor: {} }
    : { data: [{ id: "msg_one", type: "user", text: "Fix the bug", time: { created: 1 } }], cursor: { next: "next" } });
  const entries = await storage.loadTranscript("ses_one");
  assert.deepEqual(entries.map((e) => e.parts[0].text), ["Fix the bug", "[Compaction]\nEarlier decisions"]);
});

test("project deletion removes root sessions through the API and never writes database tables", async () => {
  const { createStorage } = await adapter();
  const deleted = [];
  const storage = createStorage(async (route, options) => {
    if (options.method === "DELETE") { deleted.push(route); return; }
    assert.equal(options.query.project, "project_one");
    return { data: [session("ses_one", "One"), session("ses_child", "Child", { parentID: "ses_one" })], cursor: {} };
  });
  await storage.deleteAllProjectSessions("project_one");
  assert.deepEqual(deleted, ["/api/session/ses_one"]);
});

test("content search includes transcript matches and orders title matches first", async () => {
  const { createStorage } = await adapter();
  const storage = createStorage(async (route) => {
    if (route === "/api/session") return { data: [session("ses_title", "Fix cache"), session("ses_text", "Other work")], cursor: {} };
    return { data: [{ id: "msg_one", type: "user", text: "cache invalidation", time: { created: 1 } }], cursor: {} };
  });
  assert.deepEqual((await storage.searchSessions("cache")).map((s) => s.id), ["ses_title", "ses_text"]);
});

test("liveness includes background execution and idle sessions shown in a terminal", async () => {
  const { createStorage } = await adapter();
  const storage = createStorage(async (route) => {
    assert.equal(route, "/api/session/active");
    return { data: { ses_one: { type: "running" } } };
  }, async () => ["ses_one", "ses_two"]);
  assert.deepEqual(await storage.getOpenSessions(), [
    { id: "ses_one", liveness: "active" }, { id: "ses_two", liveness: "open" },
  ]);
});

test("health-check errors become visible launcher diagnostics", async () => {
  const { createStorage } = await adapter();
  const storage = createStorage(async () => { throw new Error("HTTP 401: bad credentials"); });
  assert.match(await storage.checkDatabase(), /401: bad credentials/);
});

test("v2 canonical project paths satisfy the extension's worktree-based UI contract", async () => {
  const { createStorage } = await adapter();
  const storage = createStorage(async () => [{
    id: "project_one", canonical: "/work/repo", vcs: "git", time: { created: 1, updated: 2 }, sandboxes: [],
  }]);
  const projects = await storage.loadProjects();
  assert.equal(projects[0].worktree.split("/").at(-1), "repo");
  assert.equal(projects[0].name, null);
});

test("shell commands, exit status and captured output remain in transcripts and content search", async () => {
  const { createStorage } = await adapter();
  const storage = createStorage(async (route) => route === "/api/session"
    ? { data: [session("ses_one", "Other work")], cursor: {} }
    : { data: [{
      id: "msg_shell", type: "shell", shellID: "shell_one", command: "git status",
      status: "exited", exit: 0, time: { created: 1, completed: 2 },
      output: { output: "fixture worktree clean", cursor: 22, size: 22, truncated: false },
    }], cursor: {} });
  const transcript = await storage.loadTranscript("ses_one");
  assert.equal(transcript[0]?.parts[0]?.text, "$ git status\n[exited; exit 0]\nfixture worktree clean");
  assert.deepEqual((await storage.searchSessions("worktree clean")).map((s) => s.id), ["ses_one"]);
});
