import { execFile } from "node:child_process";
import { promisify } from "node:util";
import path from "node:path";

const execute = promisify(execFile);

export async function openSession(ctx, event, run = execute) {
  const info = event.data;
  if (event.type !== "session.created" || info?.parentID || !info?.sessionID) return;
  const directory = info.location?.directory;
  if (!directory || directory !== ctx.location.directory) return;
  // It may have been deleted or moved while waiting for a client to attach.
  const current = await ctx.session.get({ sessionID: info.sessionID });
  if (current.parentID || current.location.directory !== directory) return;
  const { stdout: panes } = await run("tmux", ["list-panes", "-a", "-F", "#{@opencode-session}"]);
  if (panes.split("\n").includes(info.sessionID)) return;
  const { stdout } = await run("tmux", ["list-sessions", "-F", "#{session_name}"]);
  const sessions = stdout.split("\n").filter(Boolean);
  if (!sessions.length) return;
  const target = sessions.includes(path.basename(directory)) ? [`-t`, `${path.basename(directory)}:`] : [];
  const title = info.title && !info.title.startsWith("New session")
    ? info.title.slice(0, 16) : `oc-${info.sessionID.slice(-4)}`;
  await run("tmux", [
    "new-window", ...target, "-c", directory, "-n", title,
    "opencode", "--session", info.sessionID,
  ]);
}

export default {
  id: "tmux-session",
  setup(ctx) {
    const controller = new AbortController();
    const timers = new Map();
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          if (event.type !== "session.created" || event.data.parentID || timers.has(event.data.sessionID)) continue;
          // Allow the TUI that created the session to publish its pane marker.
          // Telegram/headless sessions have no marker and get a new window.
          const timer = setTimeout(() => {
            void openSession(ctx, event).catch(() => {});
          }, 1500);
          timers.set(event.data.sessionID, timer);
          if (timers.size > 512) timers.delete(timers.keys().next().value);
        }
      } catch (error) {
        if (!controller.signal.aborted) console.error("[tmux-session] event stream", error);
      }
    })();
    return () => {
      controller.abort();
      for (const timer of timers.values()) clearTimeout(timer);
    };
  },
};
