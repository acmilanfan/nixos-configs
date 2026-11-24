"""The shared Ghostty config must stay platform-correct and let programs own the title."""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def config_text(host):
    configs = "darwinConfigurations" if host.startswith("mac-") else "nixosConfigurations"
    source = (
        f'let f = builtins.getFlake "{ROOT}"; '
        f'h = f.{configs}.{host}.config; '
        f'u = builtins.head (builtins.attrNames h.home-manager.users); '
        f'in h.home-manager.users.${{u}}.xdg.configFile."ghostty/config".text'
    )
    result = subprocess.run(
        ["nix", "eval", "--raw", "--no-write-lock-file", "--impure", "--expr", source],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=300,
    )
    if result.returncode:
        raise AssertionError(result.stderr[-5000:])
    return result.stdout


def validate(text):
    ghostty = shutil.which("ghostty")
    if not ghostty:
        return
    with tempfile.NamedTemporaryFile("w", suffix=".conf") as config:
        config.write(text)
        config.flush()
        result = subprocess.run(
            [ghostty, "+validate-config", f"--config-file={config.name}"],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if result.returncode:
            raise AssertionError(result.stderr or result.stdout)


class GhosttyConfig(unittest.TestCase):
    def test_linux_matches_alacritty_size(self):
        text = config_text("yogabook-gen10")
        self.assertIn("font-size = 13", text)
        validate(text)

    def test_macos_keeps_16(self):
        text = config_text("mac-home")
        self.assertIn("font-size = 16", text)
        validate(text)

    def test_title_is_not_forced(self):
        for host in ("yogabook-gen10", "mac-home"):
            with self.subTest(host=host):
                text = config_text(host)
                # A forced `title` makes Ghostty ignore the OSC titles NanoWM uses to
                # identify ORGINDEX/SCRATCHPAD/YAZI windows.
                self.assertNotIn("\ntitle = ", text)
                self.assertIn("no-title", text)

    def test_other_linux_hosts_use_13(self):
        for host in ("t480-home", "vm-hyprland"):
            with self.subTest(host=host):
                self.assertIn("font-size = 13", config_text(host))


if __name__ == "__main__":
    unittest.main()
