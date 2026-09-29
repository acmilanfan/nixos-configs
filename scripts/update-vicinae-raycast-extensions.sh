#!/usr/bin/env bash
#
# Update the pinned Raycast Store extensions in vicinae.nix.
#
# For every extension declared in `raycastExtensionSources` (built with the
# vicinae flake's mkRayCastExtension) and `raycastFodExtensions` (built via
# raycast-fod.nix):
#   1. ask the Raycast store API which commit the published version was built
#      from (source_url),
#   2. if it differs from the pinned rev, pin the new rev and resolve the
#      required hash(es) by running throwaway builds with lib.fakeHash until
#      Nix reports the real value,
#   3. do a final build with the resolved hashes to verify and populate the
#      store.
#
# Usage:
#   scripts/update-vicinae-raycast-extensions.sh          # update everything
#   scripts/update-vicinae-raycast-extensions.sh --check  # report only
#   scripts/update-vicinae-raycast-extensions.sh NAME..   # update some
#
# If an extension's store author changes (e.g. github/jira moved to
# "raycast"), update the `author` field in vicinae.nix by hand.

set -euo pipefail

FAKE="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
# Works as a repo script and as a home-manager-installed binary
# ($VICINAE_CONFIG_ROOT or the default checkout location).
ROOT="${VICINAE_CONFIG_ROOT:-$HOME/configs/nixos-configs}"
if [[ ! -f "$ROOT/flake.nix" ]]; then
  echo "nixos-configs repo not found at $ROOT (set VICINAE_CONFIG_ROOT)" >&2
  exit 1
fi
VICINAE_NIX="$ROOT/nixos/home-manager/common/vicinae.nix"
FOD_NIX="$ROOT/nixos/home-manager/common/raycast-fod.nix"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

check_only=false
if [[ "${1:-}" == "--check" ]]; then
  check_only=true
  shift
fi
wanted=("$@")

for bin in curl jq nix python3; do
  command -v "$bin" >/dev/null || { echo "missing: $bin" >&2; exit 1; }
done

# name|kind|author|rev for every managed extension
python3 - "$VICINAE_NIX" <<'PY' > "$TMP/entries.txt"
import re, sys

src = open(sys.argv[1]).read()

def blocks(section):
    m = re.search(section + r'\s*=\s*\{(.*?)\n  \};', src, re.S)
    if not m:
        sys.exit(f"section not found: {section}")
    out = []
    for b in re.finditer(r'\n    ([a-zA-Z0-9_-]+) = \{(.*?)\n    \};', m.group(1), re.S):
        out.append((b.group(1), b.group(2)))
    return out

for name, body in blocks('raycastExtensionSources'):
    author = re.search(r'author\s*=\s*"([^"]+)"', body).group(1)
    rev = re.search(r'rev\s*=\s*"([^"]+)"', body).group(1)
    print(f"{name}|mk|{author}|{rev}")

for name, body in blocks('raycastFodExtensions'):
    author = re.search(r'author\s*=\s*"([^"]+)"', body).group(1)
    rev = re.search(r'rev\s*=\s*"([^"]+)"', body).group(1)
    print(f"{name}|fod|{author}|{rev}")
PY

store_rev() { # author name
  curl -fsSL "https://backend.raycast.com/api/v1/extensions/$1/$2" 2>/dev/null |
    jq -r '.source_url // empty' 2>/dev/null |
    sed -E 's|.*/tree/([0-9a-f]+)/.*|\1|' || true
}

# got-hash from a nix build log (fails with a hash mismatch, that's the point)
disc() { # expr-file
  local log="$TMP/disc.log"
  if nix build --impure --no-link --file "$1" > "$log" 2>&1; then
    echo "BUILT_OK" # hash was already correct
  else
    grep -o 'got:[[:space:]]*sha256-[A-Za-z0-9+/=]*' "$log" | tail -1 | sed 's/got:[[:space:]]*//' || {
      echo "build failed for reasons other than a hash mismatch:" >&2
      tail -20 "$log" >&2
      exit 1
    }
  fi
}

expr_mk() { # name rev hash
  cat > "$TMP/ext.nix" <<EOF
let
  s = builtins.getFlake "path:$ROOT";
  mk = s.inputs.vicinae.lib.\${builtins.currentSystem}.mkRayCastExtension;
in
mk { name = "$1"; rev = "$2"; hash = "$3"; }
EOF
}

expr_fod() { # name dir rev sourceHash outHash
  cat > "$TMP/ext.nix" <<EOF
let
  s = builtins.getFlake "path:$ROOT";
  pkgs = s.inputs.nixpkgs.legacyPackages.\${builtins.currentSystem};
in
import $FOD_NIX {
  inherit pkgs;
  name = "$1";
  dir = "$2";
  rev = "$3";
  sourceHash = "$4";
  outHash = "$5";
}
EOF
}

fod_dir() { # name -> dir from vicinae.nix
  python3 - "$VICINAE_NIX" "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
body = re.search(r'\n    ' + re.escape(sys.argv[2]) + r' = \{(.*?)\n    \};', src, re.S).group(1)
print(re.search(r'dir\s*=\s*"([^"]+)"', body).group(1))
PY
}

set_field() { # name field value
  python3 - "$VICINAE_NIX" "$1" "$2" "$3" <<'PY'
import re, sys
path, name, field, value = sys.argv[1:5]
src = open(path).read()
pat = re.compile(r'(\n    ' + re.escape(name) + r' = \{(?:[^{}]*?))\n(    \};)', re.S)
def repl(m):
    body = re.sub(r'\n      ' + re.escape(field) + r' = "[^"]*";',
                  f'\n      {field} = "{value}";', m.group(1), count=1)
    return body + '\n' + m.group(2)
out, n = pat.subn(repl, src, count=1)
if n == 0:
    sys.exit(f"could not rewrite {name}.{field}")
open(path, 'w').write(out)
PY
}

failures=0
while IFS='|' read -r name kind author rev; do
  if [[ ${#wanted[@]} -gt 0 ]] && ! printf '%s\n' "${wanted[@]}" | grep -qx "$name"; then
    continue
  fi

  new_rev="$(store_rev "$author" "$name")"
  if [[ -z "$new_rev" ]]; then
    echo "!! $name: could not determine store source rev (author $author)"
    failures=$((failures + 1))
    continue
  fi
  if [[ "$new_rev" == "$rev" ]]; then
    echo "ok $name (up to date, $rev)"
    continue
  fi

  echo ">> $name: $rev -> $new_rev"
  if $check_only; then
    continue
  fi

  set_field "$name" rev "$new_rev"

  if [[ "$kind" == "mk" ]]; then
    expr_mk "$name" "$new_rev" "$FAKE"
    h="$(disc "$TMP/ext.nix")"
    [[ "$h" == "BUILT_OK" ]] && { echo "   hash already correct?"; continue; }
    set_field "$name" hash "$h"
    expr_mk "$name" "$new_rev" "$h"
    nix build --impure --no-link --file "$TMP/ext.nix" && echo "   verified ($h)"
  else
    dir="$(fod_dir "$name")"
    expr_fod "$name" "$dir" "$new_rev" "$FAKE" "$FAKE"
    sh="$(disc "$TMP/ext.nix")"
    set_field "$name" sourceHash "$sh"
    expr_fod "$name" "$dir" "$new_rev" "$sh" "$FAKE"
    oh="$(disc "$TMP/ext.nix")"
    set_field "$name" outHash "$oh"
    expr_fod "$name" "$dir" "$new_rev" "$sh" "$oh"
    nix build --impure --no-link --file "$TMP/ext.nix" && echo "   verified (src $sh, out $oh)"
  fi
done < "$TMP/entries.txt"

echo
if (( failures > 0 )); then
  echo "$failures extension(s) could not be checked."
  exit 1
fi
echo "Done. Rebuild with: sup"
