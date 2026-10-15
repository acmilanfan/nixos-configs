import assert from "node:assert/strict";
import test from "node:test";

const server = () => import("../agent-state.mjs");
const tui = () => import("../agent-state-tui.mjs");
const windows = () => import("../tmux-session.mjs");

function sessionContext(directory = "/work/repo") {
  return {
    location: { directory: "/work/repo" },
    session: { get: async () => ({ id: "ses_one", location: { directory } }) },
  };
}

test("a turn snapshots its session directory once before model requests and after completion", async () => {
  const { createCheckpoints } = await server();
  const calls = [];
  const hooks = createCheckpoints(sessionContext(), async (...args) => calls.push(args));
  await hooks.before({ sessionID: "ses_one" });
  await hooks.before({ sessionID: "ses_one" });
  await hooks.event({ type: "session.execution.succeeded", data: { sessionID: "ses_one" } });
  assert.deepEqual(calls, [
    ["agent-checkpoint", ["save", "pre", "ses_one", "opencode"], { cwd: "/work/repo" }],
    ["agent-checkpoint", ["save", "post", "ses_one", "opencode"], { cwd: "/work/repo" }],
  ]);
  await hooks.before({ sessionID: "ses_one" });
  assert.equal(calls.length, 3);
});

test("a plugin instance ignores sessions in other locations", async () => {
  const { createCheckpoints } = await server();
  const calls = [];
  await createCheckpoints(sessionContext("/work/other"), async (...args) => calls.push(args))
    .before({ sessionID: "ses_one" });
  assert.deepEqual(calls, []);
});

test("failed and interrupted executions close the checkpoint turn", async () => {
  const { createCheckpoints } = await server();
  for (const type of ["session.execution.failed", "session.execution.interrupted"]) {
    const calls = [];
    const hooks = createCheckpoints(sessionContext(), async (_cmd, args) => calls.push(args[1]));
    await hooks.before({ sessionID: "ses_one" });
    await hooks.event({ type, data: { sessionID: "ses_one" } });
    assert.deepEqual(calls, ["pre", "post"]);
  }
});

test("a failed session lookup does not wedge later turns for that session", async () => {
  const { createCheckpoints } = await server();
  const calls = [];
  let lookups = 0;
  const ctx = sessionContext();
  const get = ctx.session.get;
  // First lookup rejects (session deleted mid-run), later ones succeed.
  ctx.session.get = async (...args) => (++lookups === 1 ? Promise.reject(new Error("gone")) : get(...args));
  const hooks = createCheckpoints(ctx, async (_cmd, args) => calls.push(args[1]));
  await hooks.before({ sessionID: "ses_one" });
  await hooks.event({ type: "session.execution.failed", data: { sessionID: "ses_one" } });
  await hooks.before({ sessionID: "ses_one" });
  await hooks.event({ type: "session.execution.succeeded", data: { sessionID: "ses_one" } });
  assert.deepEqual(calls, ["post", "pre", "post"]);
});

function clientContext({ route = "ses_one", running = false, permission = false, form = false, outcome } = {}) {
  return {
    ui: { router: { current: () => route ? { type: "session", sessionID: route } : { type: "home" } } },
    data: {
      session: {
        get: () => ({ outcome }),
        family: () => ["ses_one", "ses_child"],
        status: (id) => id === "ses_child" && running ? "running" : "idle",
        permission: { list: (id) => id === "ses_child" && permission ? [{ id: "perm_one" }] : [] },
        form: { list: (id) => id === "ses_child" && form ? [{ id: "form_one" }] : [] },
      },
    },
  };
}

test("pane status follows only its selected session family, including child permission requests", async () => {
  const { paneStatus } = await tui();
  assert.deepEqual(paneStatus(clientContext({ running: true })), { sessionID: "ses_one", state: "running" });
  assert.equal(paneStatus(clientContext({ running: true, permission: true })).state, "needs-input");
  assert.equal(paneStatus(clientContext({ form: true })).state, "needs-input");
  assert.equal(paneStatus(clientContext()).state, "done");
  assert.deepEqual(paneStatus(clientContext({ route: null })), { sessionID: null, state: "off" });
});

test("a failed idle session needs attention, while successful idle work is done", async () => {
  const { paneStatus } = await tui();
  assert.equal(paneStatus(clientContext({ outcome: "failed" })).state, "needs-input");
  assert.equal(paneStatus(clientContext({ outcome: "succeeded" })).state, "done");
  assert.equal(paneStatus(clientContext({ outcome: "failed", running: true })).state, "running");
});

test("tmux does not open another window for a session already shown in a client", async () => {
  const { openSession } = await windows();
  const calls = [];
  await openSession(sessionContext(), {
    type: "session.created", data: { sessionID: "ses_one", location: { directory: "/work/repo" } },
  }, async (cmd, args) => {
    calls.push(args);
    return { stdout: args[0] === "list-panes" ? "ses_one\n" : "repo\n" };
  });
  assert.equal(calls.some((args) => args[0] === "new-window"), false);
});

test("headless root sessions open via v2 discovery in their own directory", async () => {
  const { openSession } = await windows();
  const calls = [];
  await openSession(sessionContext(), {
    type: "session.created", data: { sessionID: "ses_one", location: { directory: "/work/repo" } },
  }, async (cmd, args) => {
    calls.push(args);
    return { stdout: args[0] === "list-panes" ? "\n" : "repo\n" };
  });
  assert.deepEqual(calls.at(-1), [
    "new-window", "-t", "repo:", "-c", "/work/repo", "-n", "oc-_one",
    "opencode", "--session", "ses_one",
  ]);
});

test("child sessions and sessions from another plugin location do not open windows", async () => {
  const { openSession } = await windows();
  for (const data of [
    { sessionID: "ses_child", parentID: "ses_one", location: { directory: "/work/repo" } },
    { sessionID: "ses_other", location: { directory: "/work/other" } },
  ]) {
    const calls = [];
    await openSession(sessionContext(), { type: "session.created", data }, async (...args) => calls.push(args));
    assert.deepEqual(calls, []);
  }
});

test("a session deleted during the TUI grace period never opens a stale window", async () => {
  const { openSession } = await windows();
  const ctx = sessionContext();
  ctx.session.get = async () => { throw new Error("Session not found"); };
  const calls = [];
  await assert.rejects(openSession(ctx, {
    type: "session.created", data: { sessionID: "ses_deleted", location: { directory: "/work/repo" } },
  }, async (_cmd, args) => { calls.push(args); return { stdout: "repo\n" }; }), /Session not found/);
  assert.deepEqual(calls, []);
});
