#!/usr/bin/env python3
"""Evaluate maintained config and execute its generated wrapper against fixture HOME."""
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
ART = Path.home() / "ai/artifacts/org/youtube-direct-capture"


def command(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True, timeout=120)


def main():
    ART.mkdir(parents=True, exist_ok=True)
    revision = command("git", "rev-parse", "HEAD").strip()
    flake = f"git+file://{ROOT}?rev={revision}&submodules=1"
    nixpkgs = command("nix", "eval", "--raw", "--expr", f'(builtins.getFlake {json.dumps(flake)}).inputs.nixpkgs.outPath').strip()
    with tempfile.TemporaryDirectory(prefix="newsboat-fixture-", dir=ART) as temporary:
        home = Path(temporary)
        apply = f"f: f {{ nixpkgsPath = {json.dumps(nixpkgs)}; home = {json.dumps(str(home))}; }}"
        result = json.loads(command("nix", "eval", "--json", "--file", str(Path(__file__).with_name("youtube-capture-config.nix")), "--apply", apply))
        assert result["darwin"]["includesHelper"], "sup does not install the capture helper"
        assert not result["linux"]["includesHelper"], "macOS-only package added to Linux"
        darwin, linux = result["darwin"]["configText"], result["linux"]["configText"]
        assert "bookmark-autopilot yes" in darwin, "macOS capture missing"
        assert "bind-key s bookmark articlelist" in darwin and "bind-key s bookmark article" in darwin
        assert "bookmark-cmd" not in linux and "bookmark-autopilot" not in linux, "Linux capture changed"
        for config in (darwin, linux):
            assert 'bind-key ^A open-all-unread-in-browser-and-mark-read' in config
            assert "xdg-open '%u'" in config and "open '%u'" in config
        wrapper = re.search(r'^\s*bookmark-cmd "([^"]+)"', darwin, re.M).group(1)
        target = home / "nix-package/bin/youtube-org"
        target.parent.mkdir(parents=True)
        log = home / "arguments.json"
        target.write_text(f"#!/usr/bin/env python3\nimport json,sys\nfrom pathlib import Path\nPath({str(log)!r}).write_text(json.dumps(sys.argv[1:]))\nprint('Saved: 1; already present: 0; failed: 0')\nsys.exit(0)\n")
        target.chmod(0o700)
        arguments = ["https://www.youtube.com/watch?v=3V_wgHB4eFw&x=';false", "$(touch nope) \"title\"", "description", "feed"]
        result = subprocess.run(["/bin/sh", wrapper, *arguments], check=True, capture_output=True, text=True, timeout=10)
        assert result.stdout == "", "Newsboat interprets successful helper output as failure"
        assert (home / "notification").read_text().startswith("Saved: 1"), "success counts not delivered separately"
        assert json.loads(log.read_text()) == ["bookmark", *arguments], "argument boundaries lost"
        target.write_text("#!/bin/sh\nprintf 'fixture save failure\\n' >&2\nexit 7\n")
        result = subprocess.run(["/bin/sh", wrapper, *arguments], capture_output=True, text=True, timeout=10)
        assert result.returncode != 0 and "fixture save failure" in result.stdout, "Newsboat ignores stderr/exit status: save failure masked"
        target.unlink()
        result = subprocess.run(["/bin/sh", wrapper, *arguments], capture_output=True, text=True, timeout=10)
        assert result.returncode != 0 and result.stdout.strip(), "Newsboat stdout-based consumer would falsely report missing executable as success"
    print("PASS: Newsboat Darwin/Linux configuration and wrapper behavior")


if __name__ == "__main__":
    main()
