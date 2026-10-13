import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execute = promisify(execFile);
const terminalEvents = new Set([
  "session.execution.succeeded", "session.execution.failed", "session.execution.interrupted",
]);

export function createCheckpoints(ctx, run = execute) {
  const turns = new Map();
  const save = async (event, sessionID) => {
    const session = await ctx.session.get({ sessionID });
    const directory = session.location.directory;
    // Events are global; a plugin instance belongs to one location.
    if (directory !== ctx.location.directory) return;
    try {
      await run("agent-checkpoint", ["save", event, sessionID, "opencode"], { cwd: directory });
    } catch {
      // Missing helper or non-git location must not prevent a model request.
    }
  };
  return {
    async before({ sessionID }) {
      // Context runs before each agent step. Await the first snapshot on every
      // call, but do not open another turn while the execution is still active.
      if (!turns.has(sessionID)) turns.set(sessionID, save("pre", sessionID));
      await turns.get(sessionID);
    },
    async event(event) {
      const sessionID = event.data?.sessionID;
      if (!terminalEvents.has(event.type) || !turns.has(sessionID)) return;
      await turns.get(sessionID);
      turns.delete(sessionID);
      await save("post", sessionID);
    },
  };
}

export default {
  id: "agent-state",
  async setup(ctx) {
    const hooks = createCheckpoints(ctx);
    await ctx.session.hook("context", hooks.before);
    const controller = new AbortController();
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          await hooks.event(event);
        }
      } catch (error) {
        if (!controller.signal.aborted) console.error("[agent-state] event stream", error);
      }
    })();
    return () => controller.abort();
  },
};
