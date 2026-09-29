"""firefox: resolve the Firefox profile directory robustly.

Under Vicinae `getPreferenceValues` may contain a stored/default `profile_dir`
that does not match this machine (a stale ".mozilla/firefox/" value is common
on macOS). Use the preference only when it actually contains a profiles.ini,
otherwise fall back to the platform's Firefox location.
"""

import sys

PATH = "src/utils.tsx"

src = open(PATH).read()
old = "export const FIREFOX_FOLDER = path.join(homedir(), preferences.profile_dir);"
new = """function resolveFirefoxFolder(): string {
  const platformDefault =
    process.platform === "darwin" ? "Library/Application Support/Firefox/" : ".mozilla/firefox/";
  const preferred = preferences.profile_dir;
  if (preferred) {
    const candidate = path.join(homedir(), preferred);
    if (existsSync(path.join(candidate, "profiles.ini"))) return candidate;
  }
  return path.join(homedir(), platformDefault);
}

export const FIREFOX_FOLDER = resolveFirefoxFolder();"""

if old not in src:
    sys.exit("FIREFOX_FOLDER assignment not found in " + PATH)

open(PATH, "w").write(src.replace(old, new, 1))
print("patched FIREFOX_FOLDER with profiles.ini validation")
