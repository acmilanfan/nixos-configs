# AI workspace and memory

`~/ai` is an archive, not an automatically loaded memory database. It does not
need to be a Git repository.

- `projects/`: throwaway scratch clones only. Real projects stay in their normal
  directories or `wt-new` worktree siblings.
- `docs/<project>/`: research, design notes, and detailed handoffs that should
  survive removing a worktree. Include verified state, remaining work, and links
  to evidence; do not copy the entire transcript.
- `instructions/`: shared guidance fragments, read only when explicitly referenced
  or linked from a project's instructions. This README describes the layout.
- `models/`: local model downloads and caches; not agent memory.
- `artifacts/<project>/`: logs, benchmarks, transcripts, and debug output. Keep
  these out of Git and link to useful evidence rather than loading whole logs.

## OpenCode memory

Nix configures `opencode-agent-memory@0.3.0`. There is no background extraction
agent or hosted memory service, and the optional journal is disabled. Memory
tools and injected notes still consume tokens in the main model's requests.

- Global blocks: `~/.config/opencode/memory/*.md`. Keep only generic preferences
  here, never company/project details or secrets. The initial `persona` and
  `human` blocks each have a 1000-character soft budget.
- Project blocks: `<workspace>/.opencode/memory/*.md`, locally gitignored by the
  plugin. Keep one small `project` block; when first saving, set its `limit` to
  2000 using `memory_set`. The plugin's unmodified default is 5000 characters.
  All limits are soft character budgets, not hard token caps.
- The agent uses `memory_get`, `memory_set`, and `memory_replace` to maintain
  notes. Explicitly say "remember this" when a preference or decision matters.
- Injected notes are stable within a session and refreshed after compaction.
  Tools can read newer on-disk notes immediately; a fresh session sees them too.

Only configuration and initial seed templates are Nix-managed. Activation creates
missing global blocks as private writable files and never overwrites learned
notes or user-managed symlinks. Edit plugin settings in
`nixos/home-manager/common/opencode.nix`, not only the live configuration.

Project memory follows the workspace directory, so separate worktrees do not
automatically share it. Before removing a worktree, save useful discoveries or
a handoff under `~/ai/docs/<project>/`, or promote shared facts into repository
docs. Repository guidance remains the source of truth; memory is a concise aid.

## Codebase-memory trial

Trial `codebase-memory-mcp` only on explicitly selected application repositories,
not the entire home directory. Keep its index local and leave automatic indexing
of other repositories off. Compare real exploration tasks and total model usage
against ordinary searches before enabling it more broadly. Its structural index
does not replace personal preferences or debugging lessons in the notes above.

The binary is supplied by the locked unstable nixpkgs input. The initial trial
repositories are `~/Projects/wd-backend` and `~/Projects/wd-frontend`, each with
its own `.opencode/opencode.json` MCP registration and `.cbmignore` exclusions.
Project config is local to those repositories; there is no global CBM MCP entry.
The initial indexes use moderate mode; some SQL and CSS/SCSS constructs are
partially parsed. Graph results guide exploration, not proofs that a symbol or
relationship is absent. Confirm important findings against the source.
