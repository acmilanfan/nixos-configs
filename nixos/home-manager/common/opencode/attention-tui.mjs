// CLI-only replacement for the upstream `opencode.notifications` plugin
// Source: https://github.com/anomalyco/opencode/blob/v2.0.27/packages/tui/src/feature-plugins/system/notifications.ts
// Upstream MIT license: attention.LICENSE (packaged as LICENSE).
// (v2.0.27). It keeps the same event handling, deduplication, questions,
// errors, toasts, and root-session success alerts, with two changes:
//
// - Permission requests alert 1.5 seconds late, after the connected server has
//   been asked whether the request is still pending. A request answered by
//   another client (or auto-approved) before then is not announced.
// - Subagent completions and interrupted runs never alert: only real
//   questions, errors, and root-session success deserve attention.
//
// It never replies to a permission and never changes a decision. Timings are
// constants on purpose; this plugin takes no user options.
const PERMISSION_DELAY_MS = 1500;
const PERMISSION_LOOKUP_TIMEOUT_MS = 5000;
const LOOKUP_TIMED_OUT = Symbol("permission-lookup-timeout");
const LOOKUP_CANCELLED = Symbol("permission-lookup-cancelled");

// A pending entry the client cannot pin down (null, no id, wrong id type) means
// the lookup is unknown, never "this request is gone".
const isPermissionRequest = (value) =>
  typeof value === "object"
  && value !== null
  && typeof value.id === "string"
  && value.id.length > 0;

export default {
  id: "local.attention",
  setup(context) {
    const errored = new Set();
    const terminal = new Set();
    const forms = new Set();
    // id -> { sessionID, controller, timer }; presence is the dedup marker and
    // outlives the alert, so a replayed request is not announced twice.
    const permissions = new Map();
    let disposed = false;

    const notify = (sessionID, message, sound, title) => {
      const session = sessionID ? context.data.session.get(sessionID) : undefined;
      const isSubagent = session?.parentID !== undefined;
      let result;
      try {
        result = context.attention.notify({
          title: title ?? session?.title,
          message,
          notification: isSubagent ? false : { when: "blurred" },
          sound: { name: sound, when: "always" },
        });
      } catch {
        return; // Attention is best-effort; it must not break event handling.
      }
      // A rejected notification is harmless, but an unhandled rejection is not.
      if (result && typeof result.then === "function") result.then(undefined, () => {});
    };

    const started = (sessionID) => {
      errored.delete(sessionID);
      terminal.delete(sessionID);
    };

    const ended = (sessionID, alert) => {
      if (terminal.has(sessionID)) return;
      terminal.add(sessionID);
      if (errored.has(sessionID)) {
        errored.delete(sessionID);
        return;
      }
      if (!alert) return;
      const session = context.data.session.get(sessionID);
      if (session?.parentID !== undefined) return; // child completions stay quiet
      notify(sessionID, "Session done", "done");
    };

    const forgetPermission = (id) => {
      const entry = permissions.get(id);
      if (!entry) return;
      permissions.delete(id);
      clearTimeout(entry.timer);
      entry.controller?.abort();
    };

    // True while the request still needs input. A failed, malformed, or
    // nonresponsive lookup is unknown, and unknown keeps the alert rather
    // than swallowing a real request.
    const stillPending = async (id, entry, controller) => {
      let timer;
      const timeout = new Promise((resolve) => {
        timer = setTimeout(() => resolve(LOOKUP_TIMED_OUT), PERMISSION_LOOKUP_TIMEOUT_MS);
      });
      // A reply or cleanup must end the race at once: a client that ignores
      // its AbortSignal would otherwise hold this call open and keep the
      // timeout above alive until the request eventually settles.
      let cancel;
      const cancelled = new Promise((resolve) => { cancel = () => resolve(LOOKUP_CANCELLED); });
      const onAbort = () => cancel();
      controller.signal.addEventListener("abort", onAbort, { once: true });
      if (controller.signal.aborted) cancel();
      try {
        // The v2 generated client resolves the pending array directly; it is
        // not nested under `data`, and it is not `client.session.permission`.
        const listed = context.client.permission.list(
          { sessionID: entry.sessionID },
          { signal: controller.signal },
        );
        const result = await Promise.race([listed, timeout, cancelled]);
        if (result === LOOKUP_TIMED_OUT) {
          controller.abort();
          return true;
        }
        // Cancellation always comes from a reply or a cleanup, which also
        // invalidate the entry; not alerting is the safe reading if the
        // staleness guard below ever stops covering a new source.
        if (result === LOOKUP_CANCELLED) return false;
        // A malformed entry is unknown, so absence of the id proves nothing.
        if (!Array.isArray(result) || !result.every(isPermissionRequest)) return true;
        return result.some((request) => request.id === id);
      } catch {
        return true;
      } finally {
        controller.signal.removeEventListener("abort", onAbort);
        clearTimeout(timer); // the race settled, so the budget must not outlive it
      }
    };

    const schedulePermissionAlert = (id, entry) => {
      entry.timer = setTimeout(async () => {
        const controller = new AbortController();
        entry.controller = controller;
        const pending = await stillPending(id, entry, controller);
        // A reply, a cleanup, or a fresh request reusing the id may have
        // replaced this entry while the lookup ran. Only the same entry may
        // still alert.
        if (disposed || permissions.get(id) !== entry) return;
        if (!pending) return; // another client already answered it
        notify(entry.sessionID, "Permission needs input", "permission");
      }, PERMISSION_DELAY_MS);
    };

    const dispose = [
      context.data.on("form.created", (event) => {
        if (forms.has(event.data.form.id)) return;
        forms.add(event.data.form.id);
        notify(event.data.form.sessionID, "Input needs response", "question", event.data.form.title);
      }),
      context.data.on("form.replied", (event) => forms.delete(event.data.id)),
      context.data.on("form.cancelled", (event) => forms.delete(event.data.id)),
      context.data.on("permission.asked", (event) => {
        if (permissions.has(event.data.id)) return;
        const entry = { sessionID: event.data.sessionID, controller: null, timer: null };
        permissions.set(event.data.id, entry);
        schedulePermissionAlert(event.data.id, entry);
      }),
      context.data.on("permission.replied", (event) => forgetPermission(event.data.requestID)),
      context.data.on("session.execution.started", (event) => started(event.data.sessionID)),
      context.data.on("session.execution.succeeded", (event) => ended(event.data.sessionID, true)),
      context.data.on("session.execution.interrupted", (event) => ended(event.data.sessionID, false)),
      context.data.on("session.execution.failed", (event) => {
        const sessionID = event.data.sessionID;
        if (terminal.has(sessionID)) return;
        if (errored.has(sessionID)) {
          ended(sessionID, true);
          return;
        }
        errored.add(sessionID);
        notify(sessionID, event.data.error.message, "error");
        context.ui.toast.show({ sessionID, title: "Session failed", message: event.data.error.message, variant: "error" });
        ended(sessionID, true);
      }),
    ];

    return () => {
      disposed = true;
      for (const entry of permissions.values()) {
        clearTimeout(entry.timer);
        entry.controller?.abort();
      }
      permissions.clear();
      dispose.reverse().forEach((cleanup) => cleanup());
    };
  },
};
