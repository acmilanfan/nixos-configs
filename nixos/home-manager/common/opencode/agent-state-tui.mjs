import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execute = promisify(execFile);

export function paneStatus(ctx) {
  const route = ctx.ui.router.current();
  if (route.type !== "session") return { sessionID: null, state: "off" };
  const sessionID = route.sessionID;
  const family = new Set([sessionID, ...ctx.data.session.family(sessionID)]);
  const waiting = [...family].some((id) =>
    ctx.data.session.permission.list(id)?.length || ctx.data.session.form.list(id)?.length);
  const running = [...family].some((id) => ctx.data.session.status(id) === "running");
  const failed = ctx.data.session.get(sessionID)?.outcome === "failed";
  return { sessionID, state: waiting ? "needs-input" : running ? "running" : failed ? "needs-input" : "done" };
}

export default {
  id: "agent-state.tui",
  setup(ctx) {
    // This code runs in the terminal client, so TMUX_PANE refers to this
    // window even when several clients share one detached server.
    if (!process.env.TMUX || !process.env.TMUX_PANE) return;
    const pane = process.env.TMUX_PANE;
    let previous = "";
    let pending = Promise.resolve();
    const refresh = () => {
      const { sessionID, state } = paneStatus(ctx);
      const key = `${sessionID}:${state}`;
      if (key === previous) return;
      previous = key;
      pending = pending.then(async () => {
        try {
          if (sessionID) {
            await execute("tmux", ["set-option", "-p", "-t", pane, "@opencode-session", sessionID]);
          } else {
            await execute("tmux", ["set-option", "-pu", "-t", pane, "@opencode-session"]);
          }
          await execute("agent-state", ["--agent", "opencode", "--state", state]);
        } catch {
          // Closing a tmux pane or a missing optional helper is harmless.
          previous = "";
        }
      });
    };
    refresh();
    // Poll cached client state, not the API. Also catches tab/session changes
    // that emit no server event. Subprocesses run only when the state changes.
    const timer = setInterval(refresh, 500);
    return async () => {
      clearInterval(timer);
      await pending;
      await execute("agent-state", ["--agent", "opencode", "--state", "off"]).catch(() => {});
      await execute("tmux", ["set-option", "-pu", "-t", pane, "@opencode-session"]).catch(() => {});
    };
  },
};
