# NixOS & Darwin Configurations

> Single source of truth for agent instructions. `CLAUDE.md` imports this file (`@AGENTS.md`) and `GEMINI.md` redirects here, so edit **this** file when the repo changes, not those.

This repository contains Nix-based configurations for various NixOS and macOS machines, managed with Nix Flakes and Home Manager.

## Project Overview

- **Core Technologies:** Nix, NixOS, nix-darwin, Home Manager, Nix Flakes.
- **Architectures:** `x86_64-linux`, `aarch64-darwin`, and `aarch64-linux` (VM).
- **Target Machines:**
  - **NixOS:** `t480-home` (ThinkPad T480), `yogabook-gen10`, `vm-hyprland` (aarch64 Hyprland VM run under UTM on macOS).
  - **macOS:** `mac-work`, `mac-home`.
- **Key Modules:**
  - `nixos/common/`: Shared NixOS system modules, plus custom packages (`pkgs/`) and overlays (`overlays.nix`, `overlays/`).
  - `nixos/configs/`: Opt-in NixOS system modules (music, printing, Wacom, etc.) imported per host.
  - `nixos/home-manager/common/`: Shared Home Manager modules used by **every** host (Linux and macOS). Linux-only modules are added via `lib.optionals stdenv.isLinux` in its `default.nix`.
  - `nixos/home-manager/configs/`: Opt-in Home Manager modules imported per host.
  - `nixos/<host>/`: Per-host config (`configuration.nix`, `home.nix`, host-specific `configs/` and `home-manager/`). The macOS hosts' Home Manager configs also live here (`nixos/mac-work/`, `nixos/mac-home/`).
  - `darwin/`: nix-darwin system configs (`common.nix` + one file per Mac).
  - `dotfiles/`: Source for configuration files (symlinked/managed via Home Manager).
  - `apps/`: Go tools (`syncmon`, `tg2kobo`), packaged via `nixos/common/pkgs/`.
  - `shell/`: Custom nix-shell / dev-shell flakes (Java, Go/Node, Python, FHS, audio). Each flake locks the root `flake.lock`'s nixpkgs rev; after bumping nixpkgs, run `shell/update-flakes.sh` and commit the locks. `.#fhs` variants exist on Linux only.
  - `secrets/`: Private git submodule (`acmilanfan/nix-secrets`) containing only `secrets.nix`, `secrets.yaml`, its example and `.sops.yaml`. Keys and the `pass` store are in `acmilanfan/secrets`, cloned outside the flake at `~/configs/secrets` (`~/.password-store` links to its `passwords/`).
  - `docs/`: Design notes and reviews (e.g. NanoWM).

## Deployment Commands

### NixOS
To apply a configuration on a NixOS machine:
```bash
sudo nixos-rebuild switch --flake .#<hostname>
```

### macOS (nix-darwin)
To apply a configuration on a macOS machine:
```bash
sudo darwin-rebuild switch --flake .#<hostname>
```

### VM image
Build the `vm-hyprland` QEMU image from macOS (uses the nix-darwin Linux builder configured in `darwin/mac-*.nix`):
```bash
nix build .#vm-hyprland-image
```

`create-utm-vm-hyprland` builds it and creates the UTM VM; `VM_HYPRLAND_HOST=<ip> sup-vm-hyprland` deploys to a running one. The linux-builder is loaded stopped, because it holds its whole `memorySize` while running. Both scripts start it for their build and stop it afterwards; otherwise use `linux-builder start|stop|status|run <cmd>`. The first `sup` after a nixpkgs bump rebuilds the builder image, so start it first. Setup on another Mac, the remaining manual steps (disk resize, boot partition, linux-builder recovery) and why the VM's display/cursor config looks the way it does: `docs/vm-hyprland.md`.

*Note: evaluation is pure, so no `--impure`. `flake.nix` sets `inputs.self.submodules = true`, so the `secrets/` submodule is part of the flake source. It must be checked out (`git submodule update --init`), and its whole contents are copied into the world-readable `/nix/store` on every evaluation (Nix ignores `export-ignore` there). Keep only encrypted or non-sensitive data there: `flake.nix` refuses to evaluate when `secrets/` holds anything outside its allowlist, but by then the copy exists, so delete the leaked `*-source` paths with `nix-store --delete`.*

### Closed-lid operation on macOS

Both `mac-home` and `mac-work` include `no-sleep` from `darwin/common.nix`.
After applying the configuration on each Mac, use:

```bash
no-sleep on      # Keep running with the lid closed, on battery or AC
no-sleep status  # Show the system-wide sleep-disable setting (also the default command)
no-sleep off     # Allow normal macOS sleep behavior again
no-sleep toggle  # Switch between the two modes
```

SketchyBar has a clickable laptop icon next to the caffeine indicator: dim means
off, highlighted with `LID` means on, and `LID ?` means the setting could not be read.
Hammerspoon also toggles it with **Cmd+Alt+Shift+N**, **Alt+, → s → n**, or the
closed-lid entry in the keybind menu (**Alt+/** / SketchyBar's help button).
It is also searchable in the commands menu (**Alt+P**).
GUI toggles refresh the bar immediately; terminal changes appear within 30 seconds.
The indicator reads macOS's actual setting, including after boot or reload.

`on`, `off`, and `toggle` use a passwordless sudo rule restricted to those exact
subcommands of the root-owned helper, for the Mac's primary user. Installing that
rule still requires a normal authenticated Darwin rebuild.
The command uses `pmset -a disablesleep`,
so the choice persists across reboots and rebuilds. Enable it before closing the
lid for background tasks or external-display use on battery; disable it when done.
Display idle timers remain in effect. The existing Hammerspoon caffeine toggle
controls display idle sleep separately and does not provide closed-lid mode.

## Key Components & Configurations

- **Keyboard Management:** `kanata` is used heavily for keyboard remapping on both platforms (layouts in `dotfiles/kanata/`). On macOS, Karabiner-Elements is installed only for its VirtualHIDDevice driver, which kanata needs. Its grabber is deliberately disabled in `darwin/common.nix`.
- **macOS Window Management:** custom `hammerspoon` scripts (`NanoWM` tiling WM in `dotfiles/hammerspoon/nanowm/`, plus vim-navigation and key remapping) and `jankyborders`.
- **macOS Status Bar:** `sketchybar`.
- **Linux Desktops:** Hyprland (main, with `waybar` and many `hypr-*` helper scripts in `nixos/home-manager/common/scripts/`), plus AwesomeWM and GNOME.
- **Launcher:** `vicinae` on both platforms (`nixos/home-manager/common/vicinae.nix`).
- **AI Agents:** Claude Code, Gemini/Antigravity and opencode settings are generated by Nix (`nixos/home-manager/common/ai-agents.nix`, `opencode.nix`). Change them there, not in `~/.claude/settings.json` etc. The activation step warns when the live files drift from the Nix config. Because the Nix `claude` wrapper disables auto-updates (plugins included), every activation (`sup`) updates or installs the Claude Code plugins in `enabledPlugins` from their marketplaces (`claudePlugins`); the work marketplace and plugins are listed only on the work machine. Restart Claude Code sessions to load updated plugins.
- **OpenCode v2:** `pkgs.opencode` wraps the locked llm-agents `opencode2` package under the usual `opencode` command and sources runtime `ai-env.sh` for the shared service. In-app updates are disabled; use the flake and rebuild. `nix build .#opencode .#opencode-telegram-bot` builds both packages. The Telegram module runs the registered v2 service on loopback port 49374, selects `OPENCODE_SERVER_VERSION=v2`, and reads its password from the private OpenCode `service.json` at runtime. For a remote server, set `useLocalServicePassword = false` and supply credentials in the bot's private `.env`.
  The Telegram package applies `nixos/common/pkgs/opencode-telegram-bot/auto-permission-notices.patch`: background permission notices wait 1.5 seconds and check the server's pending requests before delivery, suppressing alerts already auto-approved by another client. Real pending requests still notify; lookup failures or a 5-second lookup timeout retain the alert. Project switches and runtime resets cancel stale delayed notices, while same-directory subscription refreshes preserve them. Questions and completion notices are unchanged. Package builds run typechecking, lint, and the full upstream test suite with the local regression tests. Apply with a rebuild and restart the bot (on macOS: `launchctl kickstart -k gui/$(id -u)/opencode-telegram-bot`); restarting the OpenCode server is not required for this patch.
  Terminal settings use writable `~/.config/opencode/cli.json`; `opencodeCliSettings` in `opencode.nix` manages tabs off, the Tokyonight/system theme, notifications/sounds on, prompt image previews on, transcript image previews off, and the hidden sidebar. It is merged over the live file on activation, preserving other in-app preferences (including the permission-prompt mode). Managed-field drift prints a diff and backs up the live file before restoration, keeping five `cli.json.drift.*.json` backups; formatting-only or unmanaged changes do not trigger drift warnings. `opencode/tests/cli-settings.test.mjs` takes `OPENCODE_TEST_CLI_ACTIVATION`, pointing at the Nix-evaluated activation script, to test this against isolated settings files.
  The CLI-only `attention-v2` directory plugin replaces `opencode.notifications`: permission alerts wait 1.5 seconds and check the connected server's pending requests, cancelling alerts already answered or auto-approved. Lookup errors or a 5-second timeout retain the alert. Subagent completions and interrupted executions are silent; genuine questions, errors (including child errors), and successful main-agent completion still alert. It never changes permission decisions. Activation appends the builtin-disable directive after unrelated CLI plugin entries, preserving their order/options; relocating this managed directive after a newly appended plugin can produce a one-time drift warning/backup. Tests: `opencode/tests/attention.test.mjs` and `cli-settings.test.mjs`. Apply with a rebuild and reopen terminal clients; no shared-server restart is needed.
- **OpenCode integrations:** `nixos/home-manager/common/opencode/` contains v2 server checkpoints, client-local tmux status/pane markers, and the delayed headless-session opener; Superpowers remains an upstream dual-compatible plugin. The patched Vicinae OpenCode Sessions extension reads/searches/deletes through the v2 API instead of SQLite and discovers the same local service. OpenCode v2 has no TodoWrite or built-in LSP; Neovim LSP is independent. Supported v1 provider/MCP/agent config is normalized by v2. Runtime regression tests use a separate HOME/XDG tree under `~/ai/artifacts/nixos-configs/`, a local fixture model, and a separate tmux server.
  Directory plugins must be built as a single directory and linked whole (the `agent-state-v2` Home Manager file), because v2 checks real entrypoint containment. Individual symlinks to separate store files silently skip the server plugin. Runtime tests take the built directory in `OPENCODE_TEST_PLUGIN_DIR` and exercise its real symlink layout.
  The `local` primary agent trims skill/delegation/web tool context but retains MCP and memory. `opencode/superpowers.mjs` delegates to the cached upstream plugin and skips its controller bootstrap for V2 `local`/`research` agents; other agents and V1 keep upstream behavior. `research` is for conversation and web research, with only `websearch`/`webfetch` allowed. Its short system prompt replaces the coding prompt; the configured `research-context` directory plugin runs after agent-memory and removes injected memory only for this agent. Notes, `build`, and `local` are unchanged. Normal AGENTS.md discovery still applies, so use a non-project directory to avoid repository instructions. Select the model separately from the primary agent, restart the shared service after activating adapter changes, and start a fresh session for context comparisons. `opencode/tests/superpowers.test.mjs` exercises the real cached upstream plugin (skipped when it is not installed); runtime tests take optional `OPENCODE_TEST_MEMORY_PLUGIN` to test the Nix-generated profiles with the real pinned memory implementation and a webfetch round trip.
  The opt-in `hybrid` primary agent uses GPT-6.1 Sol high with hosted `opencode-go/deepseek-v4.1-flash` children, not the local `ds4` model: `hybrid-explore` uses **low** for discovery/call-site tracing, `hybrid-review` uses **max** for independent correctness/security review, and `hybrid-worker` uses **max** for bounded coding. Explorer and reviewer are read-only with no shell/edit/Code Mode; writers inherit edit/shell approvals. Max remains the configured review/worker default, not a demonstrated quality improvement or a substitute for executed tests. No step caps are configured. Run `/hybrid <task>` to select both the profile and Sol: switching agents alone preserves the previous session model. Home requires authenticated access to the built-in OpenAI provider; work requires the configured internal OpenAI proxy to serve `gpt-6.1-sol` (not established by its older explicit model list). Flash requires OpenCode Go access on either host. For an Opus lead, select an available/authenticated Opus model separately after choosing `hybrid`; running `/hybrid` again resets it to Sol. Normal Build retains its builtin prompt, selected model and General/Explore delegation, but denies `hybrid-*` children; the global default model is unchanged. The lead is instructed to use at most two active independent children total, including discovery/review, inspect their changes, verify results, and take over after one failed correction. Prefer useful independent slices over micro-delegation; keep tightly coupled integration with the lead without making coding Sol-only. Runtime tests exercise Build catalog filtering and denied invocations, standard delegation, the Nix-generated hybrid command and real child sessions against a local fixture provider; they verify routing, stored effort selection and tool exposure, not model quality or live provider inference.
  Hybrid handoffs include preflighted checkout/environment/test/format commands, baseline failures, owned paths, acceptance cases and finite command timeouts (normally at most 120 seconds for focused worker commands; longer runs need explicit lead approval). Inspect package scripts/aliases and give exact verified executable/check invocations: adding a filename does not necessarily narrow a repo-wide writer. A worker that changes unassigned files stops edits and reports the command, affected paths and diff; it must not attempt shared-file rollback or global snapshot/Git-object/cache archaeology. The lead freezes affected paths and owns provenance-checked recovery, asking before destructive or uncertain restoration. A queued child handoff is not cancellation of its running shell command. Workers normally run focused checks; the lead owns final integrated/full-suite verification after writers finish, on frozen sources after the last edit, rerunning affected checks after later edits. Broader worker checks required by a project need a stable verification window or isolated checkout: disjoint files can share test inputs and runtime state. Negative/race cases and setup assertions apply to lead-written code too, with a separate `hybrid-review` reviewer for security/integration changes. Workers suggest notes rather than writing shared memory/global state; the lead owns bookkeeping. Reuse current canonical snapshots; scope rechecks to findings and affected dependencies, refreshing review snapshots after semantic changes. Suggest a fresh session with a short handoff for a substantial independent new task, not for compaction alone or as a forced restart. These are prompt instructions, not new permission enforcement or step limits. Config-only profiles/prompts reload without a shared-service restart after the usual rebuild (`sup`); existing sessions retain history and receive updated prompts. Fresh sessions are optional for clean comparisons or new scope.
- **Agent workflow:** `nixos/home-manager/common/agent-workflow.nix` has the t3code-inspired tooling: `wt-prune` (weekly `agent-cleanup` job removing squash-merged or long-idle empty worktrees and old checkpoints), `pr-watch` (wakes an agent's tmux pane on CI failure/green/comments/conflict), `wt-new` (worktree sibling plus an optional agent tmux session; prompts only when stdin is a terminal, otherwise takes flags such as `--task`/`--branch`/`--agent`, see `wt-new --help` and the `worktree` skill), `ai-branch-name` (used by `wt-new` to name a worktree from a task), and the shared skills folder: repo skills in `dotfiles/agent-skills/<name>/SKILL.md` are placed into `~/.claude/skills`, which Claude Code and opencode both read. Agent state per tmux pane is `@agent_state`, set by the `agent-state` wrapper in `tmux.nix`; `@agent_state_updated` records the epoch of the last hook event and drives `ai-agent-list` ordering (needs-input first, then most recent). Linked worktrees get stable ports (`WT_PORT`/`SERVER_PORT`/`PORT`) from `use_worktree_ports` in `direnv/direnvrc`.
- **OpenCode memory:** `opencode.nix` pins `opencode-agent-memory@0.3.0` with its journal disabled. Initial generic `persona`/`human` notes are seeded as private writable files under `~/.config/opencode/memory/`, never replaced on rebuild. Each has a 1000-character soft budget; project notes should use one 2000-character block under `<workspace>/.opencode/memory/` (the upstream default is 5000). Keep company/project details out of global blocks and never store secrets. Memory follows the workspace, not all worktrees: preserve useful handoffs under `~/ai/docs/<project>/` before removing a worktree. `~/ai/instructions/README.md` documents the archive/memory layout. The locked unstable `codebase-memory-mcp` binary is installed without a global MCP entry; the initial trial is scoped by local `.opencode/opencode.json` and `.cbmignore` files in `~/Projects/wd-backend` and `~/Projects/wd-frontend`. Each registration sets `codemode: false`, so the read-only `scout` tools stay on the provider's native list and a read-only agent that denies Code Mode can still query them. Because the `scout` profile never registers CBM's background watcher, the Nix-managed `cbm-refresh` command reindexes (moderate mode) only when a checkout's git HEAD/dirty signature changed, and `cbm-refresh --check` reports staleness; run it before trusting structural results. Details in `opencode/ai-workspace.md`.
- **Work MCP servers (Agent1, Jenkins, Kibana):** defined once in `nixos/home-manager/common/work-mcp.nix` and rendered for Claude Code and opencode. Endpoints and usernames come from the private `secrets.work.mcp` block (`agent1 = { qa; prod; }`, `jenkins = { username; servers.<name> = url or { url; readOnly; username; }; }`). Each service is generated only when its block exists; Kibana whenever the work marketplace is set. Credentials are sops keys (`agent1/{prod,qa}ApiKey`, `elastic/{qa,prod}ApiKey`, `jenkins/<server-name>`), exported by `ai-env.sh` only when non-empty. Configs reference them as `${VAR}` / `{env:VAR}`, so no credential is written to a config file. A missing sops key fails activation; add an empty value until the real one exists. Claude Code gets them at user scope through the `claudeMcpServers` activation. It runs `claude mcp add-json` only for changed entries, removes entries dropped from Nix (tracked in `~/.claude/.nix-mcp-servers`) and leaves hand-added servers alone. Jenkins server names follow `<area>-<env>-jenkins` (`legacy-qa-jenkins` etc.), because work skills call those tools by name; prod instances are `readOnly`. Kibana is the work marketplace's `kibana` plugin (Node 22 on PATH for it), whose `.mcp.json` owns the Kibana URLs. Its keys are the `ELASTIC_API_KEY_*` env vars; the bridge ignores a key until `check-keys.js --live` has verified it once, so run `/kibana:setup` after adding keys (it skips straight to verification). For opencode, `opencodeWorkAssets` keeps a clone of that plugin in `~/.cache/opencode-kibana-plugin` (repo taken from the marketplace manifest) and sets up what its `install-opencode.sh` would: `kibana-qa`/`kibana-prod`, started by a wrapper with the env from the plugin's `.mcp.json`, its skills (`skills/kibana`, ask for them by name) and the four app fan-out workers (`app-health`, `edge-health`, `perf-health`, `platform-health`). Env vars are read at launch: open a new shell and restart Claude Code / the opencode service after changing keys.
- **Containers:** `colima` is configured for Docker compatibility on macOS, including optimizations for Testcontainers (`nixos/common/home-darwin.nix`).
- **Secret Management:** Credentials live in the sops-encrypted `secrets/secrets.yaml` (GPG, `.sops.yaml`). They are decrypted at activation by sops-nix (`nixos/home-manager/common/sops.nix`) into runtime files: `ai-env.sh` (sourced from `.zshenv`), `~/.syncmon.yaml` and the opencode-telegram-bot `.env`. Never interpolate a credential into a Nix string, because that puts it in `/nix/store`. `secrets/secrets.nix` holds only eval-time, non-sensitive values (emails, marketplace names), passed to modules as the `secrets` argument.

## Development Conventions

- **Modularity:** Configuration is split into small single-purpose modules (e.g. `networking.nix`, `fonts.nix`, `services.nix`) under `nixos/common/` and `nixos/home-manager/common/`.
- **Shared Darwin Config:** `darwin/common.nix` contains system-level defaults, Homebrew integration, and the kanata/startup launchd services. The per-Mac files (`darwin/mac-*.nix`) set up the `nix.linux-builder` VM.
- **Home Manager:** Used for both Linux and macOS user environments. `nixos/common/home-darwin.nix` holds the shared macOS settings and imports `nixos/home-manager/common/`.
- **Package channels:** Home Manager gets both `pkgs` (stable `nixos-26.05`) and `unstable` (`nixos-unstable`) through `extraSpecialArgs`.
- **Pinned sources:** Plugins and packages built from a git checkout (custom vim plugins, tmux plugins, `blueutil-tui`, VimMode.spoon) are `flake = false` inputs in `flake.nix`, not `fetchFromGitHub` with a hand-kept hash. Use them as `src = inputs.<name>`. `pins outdated` lists the ones with new upstream commits, and `pins update [name...]` bumps only those. `awesome-wm-widgets` has its rev in the input URL (a local patch applies only to that commit), so bare `pins update` leaves it alone. Release-tagged packages (`opencode-telegram-bot`, `warpd`) still use versioned fetchers.
- **Dotfile Management:** Files in `dotfiles/` are symlinked to `$HOME` using Home Manager's `home.file` attribute.
- **Homebrew:** Homebrew's engine (`homebrew-brew`) and all six taps are `flake = false` inputs pinned in `flake.lock`. `nix-homebrew.inputs.brew-src` follows `homebrew-brew`; `darwin/common.nix` uses that source directly as `nix-homebrew.package` to avoid stale version metadata from nix-homebrew's internal lockfile. The engine tracks upstream's default branch so `up` refreshes it alongside the taps: newer formulas may require DSL features absent from nix-homebrew's default release. Both Macs and their Rosetta prefixes use `mutableTaps = false`, with `homebrew.taps` derived from `nix-homebrew.taps`. Declaring `homebrew/homebrew-core` makes the brew wrapper disable the live package API. Activation upgrades packages from the pinned definitions without updating taps. Third-party trust is declared via `nix-homebrew.trust` and mirrored into the Brewfile's tap entries so Bundle cleanup preserves it.

### Homebrew updates (macOS)

From the repository root, update the desired tap inputs and apply them:

```bash
nix flake update homebrew-brew homebrew-core homebrew-cask homebrew-formulae homebrew-autoraise homebrew-k06a homebrew-omlx
sup
```

For official packages only, use `nix flake update homebrew-brew homebrew-core homebrew-cask`. For oMLX only, use `nix flake update homebrew-omlx`. `pins update <input-name...>` also works; bare `pins update` now updates the Homebrew engine and taps as well as the other plain-source inputs. Bare `up` updates all flake inputs; `sup` applies them. Review the `flake.lock` diff to see what changed. Update `nix-homebrew` separately for changes to the installation manager. Use Nix input updates rather than `brew update` for these immutable sources.

**First activation on each existing Mac:** nix-homebrew refuses to overwrite a mutable `Library/Taps` directory. Before the first `sup`, move any existing directories aside (the backups contain tap definitions, not installed packages):

```bash
for taps in /opt/homebrew/Library/Taps /usr/local/Homebrew/Library/Taps; do
  if [ -d "$taps" ] && [ ! -L "$taps" ]; then
    sudo mv "$taps" "$taps.before-nix-$(date +%Y%m%d-%H%M%S)"
  fi
done
sup
```

This is a one-time migration; subsequent rebuilds manage the tap symlinks. The backups can be removed after a successful activation.

Pinned definitions are not exact installed-state rollback: Homebrew does not automatically downgrade packages when reverting the lockfile, and self-updating apps, moving download URLs, and formula-specific dependency installers can still drift.

### GitHub authentication for Nix

`nixos/home-manager/common/sops.nix` renders `github/personal_token` into a mode-0600 `nix-github.conf` at runtime. This personal-account credential is separate from the work credential at `github/token`, the only one with `wkda` access. `GITHUB_PERSONAL_ACCESS_TOKEN` in `ai-env.sh` (the Claude Code GitHub plugin's and opencode's MCP header) and Antigravity's GitHub MCP header use `github/token` on `mac-work` and `github/personal_token` on every other host. Home Manager's `~/.config/nix/nix.conf` includes it via `!include`, so user-level Nix commands such as `up` authenticate GitHub requests. The generated Nix-store config contains only the include path, not the token. The token is read from the file on each invocation; no shell restart is required after activation.

After applying this configuration with `sup`, use `up --refresh` to retry inputs that fell back to cached revisions because of GitHub rate limits. A successful update with `using cached version` warnings does not establish that all inputs are current. This authentication is user-level; root's Nix commands do not read the user's config.

## Key Files

- `flake.nix`: Entry point for all configurations, overlays, and the `vm-hyprland-image` package.
- `nixos/common/default.nix`: Shared NixOS system modules.
- `nixos/home-manager/common/default.nix`: Shared Home Manager modules (all hosts).
- `darwin/common.nix`: Shared macOS system modules.
- `nixos/common/home-darwin.nix`: Shared Home Manager configuration for macOS.
- `nixos/common/overlays.nix`: Custom package overlay (packages from `nixos/common/pkgs/`).
- `dotfiles/`: Contains raw configuration for tools like `kitty`, `nvim`, `hammerspoon`, `kanata`, etc.
