import { homedir } from "node:os";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const upstream = () => import(pathToFileURL(resolve(
  homedir(), ".cache/opencode-superpowers/.opencode/plugins/superpowers.js",
)).href);

// Preserve the upstream V1 entrypoint. The per-agent adapter below is V2-only.
export async function SuperpowersPlugin(ctx) {
  return (await upstream()).SuperpowersPlugin(ctx);
}

export default {
  id: "superpowers",
  server: SuperpowersPlugin,
  async setup(ctx) {
    const plugin = (await upstream()).default;
    if (!ctx?.session?.hook) return plugin.setup(ctx);
    return plugin.setup({
      ...ctx,
      session: {
        ...ctx.session,
        hook(kind, callback, ...options) {
          // Skip at the source: no dependency on ordering with memory or other
          // plugins, and no text matching that could erase user-authored input.
          const scoped = kind === "context"
            ? (event) => ["local", "research"].includes(event.agent) ? undefined : callback(event)
            : callback;
          return ctx.session.hook(kind, scoped, ...options);
        },
      },
    });
  },
};
