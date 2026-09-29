"""fuzzy-files: don't crash when there is no default file browser.

The extension resolves the default application for directories at module
scope without a catch handler:

    getDefaultApplication('inode/directory').then(v => fileBrowser = v)

On macOS Vicinae has no default opener for `inode/directory`, so the promise
rejects and the unhandled rejection kills the extension worker. Catch it and
leave `fileBrowser` unset (the extension only uses it for an "open in file
browser" action).
"""

import sys

PATH = "src/find.tsx"

src = open(PATH).read()
old = "getDefaultApplication('inode/directory').then(v => fileBrowser = v)"
new = old + ".catch(() => {})"

if old not in src:
    sys.exit("getDefaultApplication call not found in " + PATH)

src = src.replace(old, new, 1)

# `fileBrowser` is referenced unconditionally in the action panel; with no
# default opener it stays undefined and rendering crashes. Guard the action.
action_old = """                <Action.Open
                  title={`Reveal in ${fileBrowser.name}`}
                  shortcut={'open-with'}
                  icon={fileBrowser.icon}
                  target={file.path}
                  app={fileBrowser}
                />"""
action_new = """                {fileBrowser && (
                  <Action.Open
                    title={`Reveal in ${fileBrowser.name}`}
                    shortcut={'open-with'}
                    icon={fileBrowser.icon}
                    target={file.path}
                    app={fileBrowser}
                  />
                )}"""

if action_old not in src:
    sys.exit("Action.Open block not found in " + PATH)

src = src.replace(action_old, action_new, 1)
open(PATH, "w").write(src)
print("patched getDefaultApplication and fileBrowser action")
