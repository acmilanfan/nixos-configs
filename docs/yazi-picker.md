# Yazi picker on macOS

With a native **Open** or **Upload** dialog already showing:

1. Press **Ctrl+Alt+Y**.
2. Browse in the floating Ghostty/Yazi window and press **Enter** on one file.
3. The picker returns to the original dialog and selects the path using
   **Cmd+Shift+G** (Go to Folder).
4. Check the selection, then click **Open/Upload** yourself.

Press **q** in Yazi to cancel. **Alt+Y** still opens the normal Yazi file manager.
The shortcut also appears in the **Alt+/** keybind help.

Apply the configuration with `sup`; activation reloads Hammerspoon when its
managed files change. No OpenCode restart is needed.

## Limits and safeguards

- This bridges native macOS dialogs; it does not replace the system file picker.
  Custom in-app pickers, Save dialogs, and multi-file selections are unsupported.
- Starts in your home directory; it does not infer the dialog's current folder
  or enforce its file-type filter. The original dialog still decides which files
  it accepts.
- Requires the existing Ghostty launcher, Yazi, and Hammerspoon Accessibility
  permission. Automation access for Hammerspoon to control Ghostty may be
  requested on first use.
- Only one picker runs at a time. Quitting without a selection changes nothing.
- Verifies the original panel still exists and waits for the native Go to Folder
  field before writing its value directly through Accessibility. It never types
  the path as global keystrokes, never presses the final Open/Upload button,
  and does not read or replace the clipboard.
- Supports spaces, quotes, and Unicode in paths. Control characters (including
  newlines), folders, missing files, and multiple selections are rejected.
- Private chooser files are removed on completion, error, or the 30-minute
  timeout. A Hammerspoon reload during selection cancels the bridge; any orphaned
  runtime files remain in macOS's per-user temporary directory until cleaned by
  the OS. Close the orphaned Yazi window and retry the shortcut after reload.

## Verification

Regression tests run in Hammerspoon's Lua runtime with isolated window/event
boundaries; they do not type into real windows:

```sh
hs -c 'return dofile("/absolute/path/to/nixos-configs/scripts/tests/yazi-picker.test.lua")'
```

The tests cover selection, cancellation, attached sheets, duplicate invocation,
invalid paths, launch errors, focus loss, and timeouts. They cannot establish
compatibility with every application's Accessibility tree. To smoke-test an
application, open a disposable file dialog, select one file through the shortcut,
verify it is selected but not opened, then cancel the dialog. Also try **q** and
closing the original dialog while Yazi is open.
