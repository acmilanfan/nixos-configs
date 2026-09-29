"""raycast-ollama: make text-input commands work under Vicinae.

- Drop `environment.canAccess` precondition checks: Vicinae either lacks them
  or reports selected-text/clipboard access as unavailable, so commands that
  operate on selected text (the tone commands, explain, etc.) throw
  ErrorRaycastPermissionAccessibility before even trying.
- Force the input fallback on: macOS selection reading does not yield text
  under Vicinae, and preference fallbacks are not guaranteed to be present,
  so GetSelectedText/GetClipboardText should always fall back to the other
  source (clipboard first in practice).
"""

import re
import sys

PATH = "src/lib/ui/function.ts"

src = open(PATH).read()

pattern = re.compile(r"[ \t]*if \(!environment\.canAccess\([^)]*\)\) throw \w+;\n?")
src, count = pattern.subn("", src)
if count == 0:
    sys.exit("no canAccess guards found in " + PATH)

for old, new in [
    (
        "query = await GetSelectedText(p.ollamaResultViewInputFallback);",
        "query = await GetSelectedText(true);",
    ),
    (
        "query = await GetClipboardText(p.ollamaResultViewInputFallback);",
        "query = await GetClipboardText(true);",
    ),
]:
    if old not in src:
        sys.exit("anchor not found: " + old)
    src = src.replace(old, new, 1)

open(PATH, "w").write(src)
print(f"removed {count} canAccess guard(s), forced input fallbacks")
