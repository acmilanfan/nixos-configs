"""Run: python3 -m unittest discover -s tests/sketchybar -v."""
import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path.home() / "ai/artifacts/nixos-configs/sketchybar-dynamic-layer-2026-10-28"
PATCH_SHA256 = "7188a94f6379b0da34e4631eeea0f3a695245b49cf704376a4eb80f7939d7000"


class SketchyBar(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.hosts = {}
        ARTIFACTS.mkdir(parents=True, exist_ok=True)
        for host, user in (("mac-home", "gentooway"), ("mac-work", "andreishumailov")):
            expression = f'''c: let
              home = c.home-manager.users.{user};
              bars = builtins.filter (p: (p.pname or "") == "sketchybar") home.home.packages;
            in {{
              bars = map (p: {{
                version = p.version;
                patchHashes = map (path: builtins.hashFile "sha256" path) (p.patches or []);
                derivation = p.drvPath;
                package = toString p;
              }}) bars;
              defaults = toString home.home.file.".config/sketchybar/defaults.sh".source;
              failedAssertions = map (a: a.message) (builtins.filter (a: !a.assertion) c.assertions);
            }}'''
            result = subprocess.run(
                ["nix", "eval", "--json", "--no-write-lock-file",
                 f".#darwinConfigurations.{host}.config", "--apply", expression],
                cwd=ROOT, capture_output=True, text=True, timeout=120, check=True,
            )
            cls.hosts[host] = json.loads(result.stdout)
        (ARTIFACTS / "integration-evaluation.json").write_text(json.dumps(cls.hosts, indent=2) + "\n")

    def test_both_macs_ship_exact_reviewed_patch(self):
        for host, data in self.hosts.items():
            with self.subTest(host=host):
                self.assertEqual(len(data["bars"]), 1)
                bar = data["bars"][0]
                self.assertEqual(bar["version"], "2.24.1")
                self.assertIn(PATCH_SHA256, bar["patchHashes"])
                self.assertEqual(data["failedAssertions"], [])

    def test_managed_defaults_preserve_native_menu_access(self):
        for host, data in self.hosts.items():
            with self.subTest(host=host):
                result = subprocess.run(
                    ["/bin/bash", "-c", '''
sketchybar() { printf '%s\\0' "$@"; printf '\\0'; }
source "$1"
''', "defaults-check", data["defaults"]],
                    capture_output=True, timeout=10, check=True,
                )
                commands = [part.split(b"\0") for part in result.stdout.split(b"\0\0") if part]
                bars = [args for args in commands if args[0] == b"--bar"]
                self.assertEqual(len(bars), 1)
                self.assertIn(b"topmost=window", bars[0])
                self.assertNotIn(b"topmost=on", bars[0])
                self.assertIn(b"position=top", bars[0])
                self.assertIn(b"height=32", bars[0])

    def test_unreviewed_upstream_version_is_rejected(self):
        result = subprocess.run(
            ["nix", "eval", "--raw", "--file", str(ROOT / "tests/sketchybar/version-guard.nix")],
            cwd=ROOT, capture_output=True, text=True, timeout=120,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("review the macOS 27 menu-bar patch", result.stderr)


if __name__ == "__main__":
    unittest.main()
