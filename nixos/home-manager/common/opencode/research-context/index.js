export default {
  id: "research-context",
  async setup(ctx) {
    // Config loads this after agent-memory. Tool denials remove memory tools
    // from the catalog, but do not stop that plugin's system-context injection.
    await ctx.session.hook("context", (event) => {
      if (event.agent !== "research") return;
      event.system = event.system.filter((part) =>
        part.type !== "text" || !part.text.startsWith("<memory_instructions>"),
      );
    });
  },
};
