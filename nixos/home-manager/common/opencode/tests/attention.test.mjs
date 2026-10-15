// Regression tests for the CLI-only `local.attention` TUI plugin.
//
// The plugin is a fork of upstream `opencode.notifications` (v2.0.27) with two
// deliberate behavior changes: quiet subagent/interrupted completions, and
// delayed permission alerts that re-check the connected server for pending
// requests. These tests drive the real event boundary with a fake client.
import assert from "node:assert/strict";
import test from "node:test";

const plugin = () => import("../attention-tui.mjs");

const flush = () => new Promise((resolve) => setImmediate(resolve));

function deferred() {
  let resolve, reject;
  const promise = new Promise((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}

const SESSIONS = {
  ses_root: { id: "ses_root", title: "Root session" },
  ses_child: { id: "ses_child", title: "Child session", parentID: "ses_root" },
};

function harness({ sessions = SESSIONS, lookup, notify } = {}) {
  const handlers = new Map();
  const notifications = [];
  const toasts = [];
  const calls = [];
  const context = {
    data: {
      on(type, handler) {
        const listeners = handlers.get(type) ?? new Set();
        listeners.add(handler);
        handlers.set(type, listeners);
        return () => listeners.delete(handler);
      },
      session: { get: (id) => sessions[id] },
    },
    attention: {
      notify: notify ?? ((options) => { notifications.push(options); return Promise.resolve({ ok: true }); }),
    },
    ui: { toast: { show: (options) => toasts.push(options) } },
    client: {
      permission: {
        // May throw synchronously, like a missing or broken client.
        list: (input, options) => {
          calls.push([input, options]);
          return lookup ? lookup(input, options) : Promise.resolve([]);
        },
      },
    },
  };
  return {
    context, notifications, toasts, calls,
    emit(type, data) {
      for (const handler of [...(handlers.get(type) ?? [])]) handler({ type, data });
    },
    listenerCount: (type) => (handlers.get(type) ?? new Set()).size,
  };
}

async function load(options) {
  const attention = (await plugin()).default;
  assert.equal(attention.id, "local.attention");
  const h = harness(options);
  h.cleanup = attention.setup(h.context);
  return h;
}

const expectPermission = (session) => ({
  title: session.title,
  message: "Permission needs input",
  notification: session.parentID !== undefined ? false : { when: "blurred" },
  sound: { name: "permission", when: "always" },
});

const expectQuestion = (title, session) => ({
  title,
  message: "Input needs response",
  notification: session?.parentID !== undefined ? false : { when: "blurred" },
  sound: { name: "question", when: "always" },
});

// Node's mock timers expose no pending-timer introspection, so wrap the global
// timer functions in the test to see which handles are still live. Production
// code keeps using plain setTimeout/clearTimeout.
function installTimerRegistry(t) {
  const live = new Set();
  const originalSet = globalThis.setTimeout;
  const originalClear = globalThis.clearTimeout;
  const wrappedSet = (callback, delay, ...args) => {
    const handle = originalSet((...callbackArgs) => {
      live.delete(handle);
      callback(...callbackArgs);
    }, delay, ...args);
    live.add(handle);
    return handle;
  };
  const wrappedClear = (handle) => {
    live.delete(handle);
    return originalClear(handle);
  };
  globalThis.setTimeout = wrappedSet;
  globalThis.clearTimeout = wrappedClear;
  t.after(() => {
    // The test runner restores its own globals when per-test mocks reset, so
    // only undo the wrapper while it is still installed.
    if (globalThis.setTimeout === wrappedSet) globalThis.setTimeout = originalSet;
    if (globalThis.clearTimeout === wrappedClear) globalThis.clearTimeout = originalClear;
  });
  return live;
}

test("a root completion notifies once and subagent completions stay silent", async () => {
  const h = await load();
  h.emit("session.execution.started", { sessionID: "ses_root" });
  h.emit("session.execution.succeeded", { sessionID: "ses_root" });
  assert.deepEqual(h.notifications, [{
    title: "Root session", message: "Session done",
    notification: { when: "blurred" }, sound: { name: "done", when: "always" },
  }]);

  h.emit("session.execution.started", { sessionID: "ses_child" });
  h.emit("session.execution.succeeded", { sessionID: "ses_child" });
  h.emit("session.execution.succeeded", { sessionID: "ses_child" });
  assert.equal(h.notifications.length, 1);

  // Repeated terminal events for the same run never notify twice.
  h.emit("session.execution.succeeded", { sessionID: "ses_root" });
  assert.equal(h.notifications.length, 1);
  await h.cleanup();
});

test("a later run of the same session alerts again", async () => {
  const h = await load();
  const done = { title: "Root session", message: "Session done",
    notification: { when: "blurred" }, sound: { name: "done", when: "always" } };
  h.emit("session.execution.started", { sessionID: "ses_root" });
  h.emit("session.execution.succeeded", { sessionID: "ses_root" });
  h.emit("session.execution.succeeded", { sessionID: "ses_root" });
  assert.deepEqual(h.notifications, [done]);

  // A new start clears the terminal dedup set, so the next success alerts.
  h.emit("session.execution.started", { sessionID: "ses_root" });
  h.emit("session.execution.succeeded", { sessionID: "ses_root" });
  assert.deepEqual(h.notifications, [done, done]);
  await h.cleanup();
});

test("interrupted runs never notify, and still close their run", async () => {
  const h = await load();
  for (const sessionID of ["ses_root", "ses_child"]) {
    h.emit("session.execution.started", { sessionID });
    h.emit("session.execution.interrupted", { sessionID });
    // Interruption is terminal, so a late success cannot re-alert either.
    h.emit("session.execution.succeeded", { sessionID });
  }
  assert.deepEqual(h.notifications, []);
  await h.cleanup();
});

test("questions notify with the form title, dedupe by form id, and clear on reply or cancel", async () => {
  const h = await load();
  const ask = (form) => h.emit("form.created", { form });
  ask({ id: "form_one", sessionID: "ses_root", title: "Answer me" });
  ask({ id: "form_one", sessionID: "ses_root", title: "Answer me" });
  assert.deepEqual(h.notifications, [expectQuestion("Answer me", SESSIONS.ses_root)]);

  h.emit("form.replied", { id: "form_one" });
  ask({ id: "form_one", sessionID: "ses_root", title: "Answered" });
  h.emit("form.cancelled", { id: "form_one" });
  ask({ id: "form_one", sessionID: "ses_root", title: "Cancelled" });
  assert.deepEqual(h.notifications.map((n) => n.title), ["Answer me", "Answered", "Cancelled"]);

  ask({ id: "form_child", sessionID: "ses_child", title: "Child question" });
  assert.deepEqual(h.notifications.at(-1), expectQuestion("Child question", SESSIONS.ses_child));

  // Global forms carry no session and still alert like a root session.
  ask({ id: "form_global", title: "Global question" });
  assert.deepEqual(h.notifications.at(-1), expectQuestion("Global question", undefined));
  await h.cleanup();
});

test("failed runs notify and toast once, keeping the error sound for children", async () => {
  const h = await load();
  h.emit("session.execution.started", { sessionID: "ses_root" });
  h.emit("session.execution.failed", { sessionID: "ses_root", error: { message: "boom" } });
  h.emit("session.execution.failed", { sessionID: "ses_root", error: { message: "boom" } });
  assert.deepEqual(h.notifications, [{
    title: "Root session", message: "boom",
    notification: { when: "blurred" }, sound: { name: "error", when: "always" },
  }]);
  assert.deepEqual(h.toasts, [{
    sessionID: "ses_root", title: "Session failed", message: "boom", variant: "error",
  }]);

  h.emit("session.execution.started", { sessionID: "ses_child" });
  h.emit("session.execution.failed", { sessionID: "ses_child", error: { message: "child boom" } });
  assert.equal(h.notifications.at(-1).notification, false);
  assert.equal(h.notifications.at(-1).sound.name, "error");
  assert.equal(h.toasts.at(-1).sessionID, "ses_child");
  await h.cleanup();
});

test("a rejected attention notification is swallowed", async () => {
  const h = await load({
    notify: (options) => {
      h.notifications.push(options);
      return Promise.reject(new Error("attention offline"));
    },
  });
  h.emit("form.created", { form: { id: "form_one", sessionID: "ses_root", title: "Answer me" } });
  await flush();
  await flush();
  // Node's test runner fails this test if the rejection is left unhandled.
  assert.equal(h.notifications.length, 1);
  await h.cleanup();
});

test("a pending permission notifies after the delay, using the client's session list", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const h = await load({ lookup: () => Promise.resolve([{ id: "perm_one" }, { id: "perm_child" }]) });
  h.emit("permission.asked", { id: "perm_one", sessionID: "ses_root" });
  h.emit("permission.asked", { id: "perm_one", sessionID: "ses_root" });
  t.mock.timers.tick(1499);
  await flush();
  assert.deepEqual(h.notifications, []);
  assert.deepEqual(h.calls, []);

  t.mock.timers.tick(1);
  await flush();
  assert.equal(h.calls.length, 1);
  assert.deepEqual(h.calls[0][0], { sessionID: "ses_root" });
  assert.deepEqual(Object.keys(h.calls[0][1]), ["signal"]);
  assert.equal(h.calls[0][1].signal.aborted, false);
  assert.deepEqual(h.notifications, [expectPermission(SESSIONS.ses_root)]);

  // A child request keeps the sound but never a desktop notification.
  h.emit("permission.asked", { id: "perm_child", sessionID: "ses_child" });
  t.mock.timers.tick(1500);
  await flush();
  assert.deepEqual(h.notifications.at(-1), expectPermission(SESSIONS.ses_child));
  await h.cleanup();
});

test("a request resolved on the server without a reply event stays silent", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const h = await load({ lookup: () => Promise.resolve([{ id: "perm_other" }]) });
  h.emit("permission.asked", { id: "perm_one", sessionID: "ses_root" });
  t.mock.timers.tick(1500);
  await flush();
  assert.equal(h.calls.length, 1);
  assert.deepEqual(h.notifications, []);
  await h.cleanup();
});

test("a reply cancels the alert, before or during the lookup", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const early = await load({ lookup: () => Promise.resolve([{ id: "perm_one" }]) });
  early.emit("permission.asked", { id: "perm_one", sessionID: "ses_root" });
  early.emit("permission.replied", { requestID: "perm_one" });
  t.mock.timers.tick(5000);
  await flush();
  assert.deepEqual(early.notifications, []);
  assert.deepEqual(early.calls, []);
  await early.cleanup();

  const listed = deferred();
  const h = await load({ lookup: () => listed.promise });
  h.emit("permission.asked", { id: "perm_one", sessionID: "ses_root" });
  t.mock.timers.tick(1500);
  await flush();
  assert.equal(h.calls.length, 1);

  h.emit("permission.replied", { requestID: "perm_one" });
  assert.equal(h.calls[0][1].signal.aborted, true);
  listed.resolve([{ id: "perm_one" }]);
  await flush();
  assert.deepEqual(h.notifications, []);
  await h.cleanup();
});

test("a reply still suppresses the alert when the lookup result is already queued", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const h = await load({ lookup: () => Promise.resolve([{ id: "perm_one" }]) });
  h.emit("permission.asked", { id: "perm_one", sessionID: "ses_root" });
  t.mock.timers.tick(1500);
  // The client answered inside the same tick, so its race result is already
  // queued, and the reply lands before that result is consumed: only the
  // entry identity can still reject this alert.
  h.emit("permission.replied", { requestID: "perm_one" });
  await flush();
  assert.equal(h.calls.length, 1);
  assert.deepEqual(h.notifications, []);
  await h.cleanup();
});

test("lookup failures, malformed payloads, and timeouts retain the alert", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const cases = {
    "a rejected lookup": () => Promise.reject(new Error("offline")),
    "a malformed payload": () => Promise.resolve({ data: [{ id: "perm_one" }] }),
    // Not an array. Without the array check, a lookalike that answers both
    // shape probes reads as resolved.
    "a non-array lookalike": () => Promise.resolve({ every: () => true, some: () => false }),
    // A malformed entry must read as unknown, not as absence of the request.
    "a null entry": () => Promise.resolve([null]),
    "an entry without an id": () => Promise.resolve([{}]),
    "an entry with a numeric id": () => Promise.resolve([{ id: 123 }]),
    "an entry with an empty id": () => Promise.resolve([{ id: "" }]),
    "a malformed entry beside a valid one": () => Promise.resolve([{ id: "perm_other" }, null]),
    "a missing payload": () => Promise.resolve(undefined),
    "a throwing client": () => { throw new Error("no client"); },
  };
  for (const [name, lookup] of Object.entries(cases)) {
    const h = await load({ lookup });
    h.emit("permission.asked", { id: "perm_one", sessionID: "ses_root" });
    t.mock.timers.tick(1500);
    await flush();
    assert.deepEqual(h.notifications, [expectPermission(SESSIONS.ses_root)], name);
    await h.cleanup();
  }

  // A nonresponsive client is aborted when the 5s lookup budget runs out.
  const stalled = deferred();
  const h = await load({ lookup: () => stalled.promise });
  h.emit("permission.asked", { id: "perm_one", sessionID: "ses_root" });
  t.mock.timers.tick(1500);
  await flush();
  assert.deepEqual(h.notifications, []);
  t.mock.timers.tick(4999);
  await flush();
  assert.deepEqual(h.notifications, []);
  t.mock.timers.tick(1);
  await flush();
  assert.deepEqual(h.notifications, [expectPermission(SESSIONS.ses_root)]);
  assert.equal(h.calls[0][1].signal.aborted, true);
  await h.cleanup();
});

test("cleanup cancels delayed and in-flight permission work and its subscriptions", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const delayed = await load({ lookup: () => Promise.resolve([{ id: "perm_one" }]) });
  delayed.emit("permission.asked", { id: "perm_one", sessionID: "ses_root" });
  await delayed.cleanup();
  t.mock.timers.tick(5000);
  await flush();
  assert.deepEqual(delayed.notifications, []);
  assert.deepEqual(delayed.calls, []);

  const listed = deferred();
  const inflight = await load({ lookup: () => listed.promise });
  inflight.emit("permission.asked", { id: "perm_one", sessionID: "ses_root" });
  t.mock.timers.tick(1500);
  await flush();
  assert.equal(inflight.calls.length, 1);
  await inflight.cleanup();
  assert.equal(inflight.calls[0][1].signal.aborted, true);
  listed.resolve([{ id: "perm_one" }]);
  await flush();
  assert.deepEqual(inflight.notifications, []);

  inflight.emit("form.created", { form: { id: "form_late", sessionID: "ses_root", title: "Late" } });
  assert.deepEqual(inflight.notifications, []);
  assert.equal(inflight.listenerCount("form.created"), 0);
});

test("a reply or cleanup ends the lookup race at once and clears its 5s timeout", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const live = installTimerRegistry(t);
  // The client never settles and ignores its AbortSignal.
  const stalled = await load({ lookup: () => new Promise(() => {}) });
  stalled.emit("permission.asked", { id: "perm_one", sessionID: "ses_root" });
  assert.equal(live.size, 1, "the 1.5s delay is armed");
  t.mock.timers.tick(1500);
  await flush();
  assert.equal(stalled.calls.length, 1, "the lookup started");
  assert.equal(live.size, 1, "only the 5s lookup budget remains armed");

  stalled.emit("permission.replied", { requestID: "perm_one" });
  await flush();
  assert.equal(live.size, 0, "the reply cleared the delay and lookup timers");
  // Nothing can fire later: no pending timer, no late alert.
  t.mock.timers.tick(10_000);
  await flush();
  assert.deepEqual(stalled.notifications, []);
  await stalled.cleanup();

  const inflight = await load({ lookup: () => new Promise(() => {}) });
  inflight.emit("permission.asked", { id: "perm_one", sessionID: "ses_root" });
  t.mock.timers.tick(1500);
  await flush();
  assert.equal(live.size, 1, "only the 5s lookup budget remains armed");
  await inflight.cleanup();
  await flush();
  assert.equal(live.size, 0, "cleanup cleared the delay and lookup timers");
  t.mock.timers.tick(10_000);
  await flush();
  assert.deepEqual(inflight.notifications, []);
});

test("a reused id never alerts from the previous lookup", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const first = deferred();
  const second = deferred();
  const lookups = [first.promise, second.promise];
  const h = await load({ lookup: () => lookups.shift() });
  h.emit("permission.asked", { id: "perm_one", sessionID: "ses_root" });
  t.mock.timers.tick(1500);
  await flush();
  assert.equal(h.calls.length, 1);

  h.emit("permission.replied", { requestID: "perm_one" });
  h.emit("permission.asked", { id: "perm_one", sessionID: "ses_root" });
  first.resolve([{ id: "perm_one" }]);
  await flush();
  assert.deepEqual(h.notifications, [], "the answered request must not alert");

  t.mock.timers.tick(1500);
  await flush();
  assert.equal(h.calls.length, 2);
  assert.equal(h.calls[1][1].signal.aborted, false);
  second.resolve([{ id: "perm_one" }]);
  await flush();
  assert.deepEqual(h.notifications, [expectPermission(SESSIONS.ses_root)]);
  await h.cleanup();
});
