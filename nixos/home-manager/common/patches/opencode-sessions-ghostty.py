"""Replace opencode-sessions' Ghostty integration with Ghostty's scripting API.

The upstream implementation drives Ghostty via AppleScript + System Events
keystrokes, which requires Accessibility/Automation TCC permissions that a
helper process spawned by Vicinae cannot obtain. Ghostty (>= 1.2) exposes a
scripting API that can create a window with an initial working directory and
input, so no keystrokes are needed.
"""

import re
import sys

PATH = "src/lib/terminal.ts"

src = open(PATH).read()
pattern = re.compile(
    r"async function openInGhostty\(directory: string, command: string\): Promise<void> \{.*?\n\}",
    re.S,
)
replacement = """async function openInGhostty(directory: string, command: string): Promise<void> {
  await runAppleScript(`
    tell application "Ghostty"
      set cfg to new surface configuration
      set initial working directory of cfg to "${esc(directory)}"
      set initial input of cfg to "${esc(command)}" & linefeed
      new window with configuration cfg
    end tell
  `);
}"""

patched, count = pattern.subn(replacement, src, count=1)
if count != 1:
    sys.exit("openInGhostty not found in " + PATH)

src = patched

# Prefer tmux for resumed sessions when a tmux server is already running:
#   1. if some tmux session has a pane rooted in the same directory, open the
#      opencode session as a new WINDOW in that session;
#   2. otherwise create/attach a dedicated session so the work survives the
#      terminal window.
resume_old = """export async function resumeSession(directory: string, sessionId: string, isOpen: boolean = false): Promise<void> {
  const cmd = `opencode -s ${shellQuote(sessionId)}`;
  const terminal = getTerminal();"""

resume_new = """export async function resumeSession(directory: string, sessionId: string, isOpen: boolean = false): Promise<void> {
  let cmd = `opencode -s ${shellQuote(sessionId)}`;
  const terminal = getTerminal();

  // 1. Existing tmux session with a pane rooted in this directory:
  //    open the session as a new window there and switch attached clients to
  //    it (an attached session is preferred over a detached one).
  try {
    const panes = execSync("tmux list-panes -a -F '#{session_name}\t#{pane_current_path}\t#{session_attached}'", {
      encoding: "utf-8",
    });
    const rows = panes
      .split("\\n")
      .filter(Boolean)
      .map((line) => line.split("\\t"));
    const match = rows.find(([, path, attached]) => path === directory && attached !== "0") ??
      rows.find(([, path]) => path === directory);
    if (match) {
      const session = match[0];
      const win = execSync(
        `tmux new-window -P -F '#{window_id}' -t ${shellQuote(session)} -c ${shellQuote(directory)} ${shellQuote(cmd)}`,
        { encoding: "utf-8" },
      ).trim();
      if (win) {
        execSync(`tmux select-window -t ${shellQuote(win)}`, { stdio: "ignore" });
        // Select-window only changes the session's current window; switch the
        // attached clients so the new window is actually displayed. If the
        // session is detached, move the most recently active client over.
        let clients: string[] = [];
        try {
          clients = execSync(`tmux list-clients -t ${shellQuote(session)} -F '#{client_name}'`, { encoding: "utf-8" })
            .split("\\n")
            .map((s) => s.trim())
            .filter(Boolean);
        } catch {
          // no attached clients
        }
        if (clients.length === 0) {
          try {
            const recent = execSync("tmux list-clients -F '#{client_name}\\t#{client_activity}'", { encoding: "utf-8" })
              .split("\\n")
              .filter(Boolean)
              .map((line) => line.split("\\t"))
              .sort((a, b) => Number(b[1]) - Number(a[1]))[0];
            if (recent) clients = [recent[0]];
          } catch {
            // no clients at all
          }
        }
        for (const client of clients) {
          execSync(`tmux switch-client -c ${shellQuote(client)} -t ${shellQuote(win)}`, { stdio: "ignore" });
        }
      }
      // Raise the terminal so the switched-to tmux window is visible (and so
      // window managers that follow focused apps switch to the terminal's tag).
      const terminalApps: Record<string, string> = { ghostty: "Ghostty", kitty: "kitty", iterm2: "iTerm2", warp: "Warp", terminal: "Terminal" };
      try {
        if (terminalApps[terminal]) execSync(`osascript -e 'tell application "${terminalApps[terminal]}" to activate'`);
      } catch {
        // ignore
      }
      await closeMainWindow({ clearRootSearch: true }).catch(() => undefined);
      return;
    }
  } catch {
    // no tmux server running (or no matching pane)
  }

  // 2. Otherwise, if a tmux server is running, create/attach a dedicated
  //    session so the work survives the terminal window.
  try {
    execSync("tmux list-sessions", { stdio: "ignore" });
    cmd = `tmux new-session -A -s ${shellQuote(`opencode-${sessionId}`)} ${shellQuote(cmd)}`;
  } catch {
    // no tmux server running; fall through with the plain command
  }"""

if resume_old not in src:
    sys.exit("resumeSession not found in " + PATH)

src = src.replace(resume_old, resume_new, 1)

# closeMainWindow is needed for the tmux path (no focus theft happens there).
import_old = 'import { getPreferenceValues } from "@raycast/api";'
import_new = 'import { closeMainWindow, getPreferenceValues } from "@raycast/api";'
if import_old not in src:
    sys.exit("raycast api import not found in " + PATH)

src = src.replace(import_old, import_new, 1)

open(PATH, "w").write(src)
print("patched openInGhostty and resumeSession (tmux)")
