"""Evaluate real host modules and parse their outputs with OpenSSH.

Run: python3 -m unittest discover -s tests/remote-access -p 'test_*.py' -v
No live service, user key, account enrollment or tmux session is touched.
"""

import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path.home() / "ai/artifacts/nixos-configs/remote-access"
ALLOW_USERS = [
    "gentooway@100.64.0.0/10",
    "gentooway@fd7a:115c:a1e0::/48",
]
OWNED_ADDITIONS = [
    "darwin/remote-access.nix",
    "nixos/configs/remote-access.nix",
    "nixos/home-manager/configs/remote-access.nix",
    "docs/remote-access.md",
    "tests/remote-access/eval.nix",
    "tests/remote-access/test_remote_access.py",
]
SAFE_SUBMODULE_FILES = [
    "secrets/.sops.yaml", "secrets/secrets.nix",
    "secrets/secrets.yaml", "secrets/secrets.yaml.example",
]


def source_entries(root):
    names = run(
        "git", "-C", str(root), "ls-files", "-z", "--cached"
    ).stdout.split("\0")
    # Untracked files are never presumed safe for a world-readable store copy.
    # Add only reviewed task sources and the submodule's explicit safe files.
    names += [
        name for name in OWNED_ADDITIONS + SAFE_SUBMODULE_FILES
        if (root / name).is_file()
    ]
    entries = set()
    for name in names:
        path = Path(name)
        if not name or any(p in {".git", ".opencode", "__pycache__"} for p in path.parts):
            continue
        entries.add(name)
        entries.update(str(p) for p in path.parents if str(p) != ".")
    return sorted(entries)


def run(*args):
    result = subprocess.run(args, text=True, capture_output=True, timeout=120)
    if result.returncode:
        raise RuntimeError(f"{args!r} exited {result.returncode}:\n{result.stderr}\n{result.stdout}")
    return result


def directives(text):
    result = {}
    for line in text.splitlines():
        key, _, value = line.partition(" ")
        key = key.lower()
        # sshd -T emits one line per AllowUsers entry. Keep all values so a
        # permissive earlier entry cannot disappear from the assertion.
        result[key] = (result[key] + " " + value.strip()) if key in result else value.strip()
    return result


class RemoteAccess(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        ARTIFACTS.mkdir(parents=True, exist_ok=True)
        # Git tracks the submodule, not its children. Only these explicitly safe
        # files belong in the flake source; never traverse .git or private data.
        manifest = ARTIFACTS / "source-manifest.json"
        manifest.write_text(json.dumps(source_entries(ROOT)))
        result = run(
            "nix", "eval", "--impure", "--json", "--no-write-lock-file",
            "--file", str(ROOT / "tests/remote-access/eval.nix"),
            "--apply", f"f: f {{ repo = {json.dumps(str(ROOT))}; manifest = {json.dumps(str(manifest))}; }}",
        )
        (ARTIFACTS / "evaluation.json").write_text(result.stdout)
        (ARTIFACTS / "evaluation.stderr").write_text(result.stderr)
        cls.hosts = json.loads(result.stdout)

    def test_intended_hosts_have_tailscale_and_ssh(self):
        for name in ("mac-home", "yogabook", "t480"):
            with self.subTest(host=name):
                self.assertTrue(self.hosts[name]["tailscale"])
                self.assertTrue(self.hosts[name]["ssh"])
        self.assertTrue(self.hosts["mac-home"]["tailscaleAtBoot"])
        self.assertFalse(self.hosts["mac-home"]["dnsOverride"])

    def test_tailscale_ssh_server_is_disabled_at_daemon_start(self):
        # Daemon-level gate prevents persisted RunSSH=true prefs from taking
        # over TCP/22 before a later oneshot/activation can clear the preference.
        for name in ("mac-home", "yogabook", "t480"):
            with self.subTest(host=name):
                self.assertEqual(self.hosts[name]["tailscaleSSHDisabled"], "true")

    def test_linux_ssh_is_not_open_on_physical_interfaces(self):
        for name in ("yogabook", "t480"):
            with self.subTest(host=name):
                host = self.hosts[name]
                self.assertFalse(host["sshOpenFirewall"])
                self.assertNotIn(22, host["globalTCPPorts"])
                self.assertEqual(host["tailnetTCPPorts"], [22])
                self.assertEqual(host["trustedInterfaces"], ["lo"])
                self.assertTrue(host["tailscaleOpenFirewall"])
                self.assertEqual(host["reversePath"], "loose")
                self.assertEqual(host["routing"], "none")
                self.assertIsNone(host["authKeyFile"])
                self.assertIn("--netfilter-mode=off", host["tailscaleSetFlags"])
                self.assertIn("--ssh=false", host["tailscaleSetFlags"])

    def test_linux_authentication_is_key_only_and_tailnet_user_only(self):
        for name in ("yogabook", "t480"):
            with self.subTest(host=name):
                settings = self.hosts[name]["sshSettings"]
                self.assertFalse(settings["PasswordAuthentication"])
                self.assertFalse(settings["KbdInteractiveAuthentication"])
                self.assertEqual(settings["PermitRootLogin"], "no")
                self.assertEqual(settings.get("AuthenticationMethods"), "publickey")
                self.assertEqual(settings.get("AllowUsers"), ALLOW_USERS)

    def test_mac_uses_key_only_tailnet_authentication(self):
        settings = directives(self.hosts["mac-home"]["sshExtraConfig"])
        self.assertEqual(settings.get("passwordauthentication"), "no")
        self.assertEqual(settings.get("kbdinteractiveauthentication"), "no")
        self.assertEqual(settings.get("permitrootlogin"), "no")
        self.assertEqual(settings.get("authenticationmethods"), "publickey")
        self.assertEqual(settings.get("allowusers", "").split(), ALLOW_USERS)

    def test_unrelated_hosts_do_not_get_remote_access(self):
        for name in ("mac-work", "vm"):
            with self.subTest(host=name):
                self.assertFalse(self.hosts[name]["tailscale"])
                self.assertEqual(self.hosts[name]["aliases"], [])
        self.assertEqual(
            directives(self.hosts["mac-work"]["sshExtraConfig"])["allowusers"],
            "andreishumailov",
        )
        self.assertTrue(self.hosts["vm"]["ssh"])
        self.assertEqual(self.hosts["vm"]["hostName"], "vm-hyprland")

    def test_hosts_evaluate_without_failed_assertions(self):
        for name, config in self.hosts.items():
            with self.subTest(host=name):
                self.assertEqual(config["failedAssertions"], [])

    def test_ssh_aliases_route_only_through_tailscale(self):
        ssh = shutil.which("ssh")
        if not ssh:
            self.skipTest("OpenSSH client unavailable")
        for name in ("mac-home", "yogabook", "t480"):
            host = self.hosts[name]
            self.assertEqual(host["aliases"], ["mac-home", "yogabook", "t480"])
            config = ARTIFACTS / f"{name}-ssh_config"
            config.write_text(host["sshConfig"])
            for alias, target in (("mac-home", "mac-home"), ("yogabook", "yogabook"), ("t480", "t480-nixos")):
                with self.subTest(source=name, destination=alias):
                    parsed = directives(run(ssh, "-G", "-F", str(config), alias).stdout)
                    self.assertEqual(parsed["hostname"], target)
                    self.assertEqual(parsed["user"], "gentooway")
                    self.assertEqual(parsed["identityfile"], "~/.ssh/id_ed25519_remote")
                    self.assertEqual(parsed["identitiesonly"], "yes")
                    self.assertEqual(parsed["forwardagent"], "no")
                    self.assertEqual(parsed["passwordauthentication"], "no")
                    self.assertEqual(parsed["stricthostkeychecking"], "ask")
                    self.assertEqual(parsed["serveraliveinterval"], "30")
                    self.assertEqual(parsed["serveralivecountmax"], "3")
                    self.assertEqual(parsed["connecttimeout"], "10")
                    self.assertIn("/bin/tailscale ip -4", parsed["proxycommand"])
                    self.assertIn("/bin/tailscale nc", parsed["proxycommand"])
                    self.assertEqual(parsed.get("remotecommand", "none"), "none")

    def test_proxy_requires_a_registered_peer_before_dialing(self):
        # The real `tailscale nc` can resolve/fall back to non-tailnet hosts.
        # Substitute only the external CLI boundary, then execute our actual
        # evaluated ProxyCommand shell logic: absent peers must never dial.
        ssh = shutil.which("ssh")
        if not ssh:
            self.skipTest("OpenSSH client unavailable")
        with tempfile.TemporaryDirectory(prefix="proxy-fixture-", dir=ARTIFACTS) as temp:
            cli = Path(temp) / "tailscale"
            cli.write_text('''#!/bin/sh
case "$1" in
  ip)
    [ "$2" = -4 ] && [ "$3" = mac-home ] || exit 97
    [ "$PEER_PRESENT" != no ] || exit 1
    printf '100.100.1.2\\n'
    ;;
  nc)
    [ "$PEER_PRESENT" != removed ] || exit 2
    printf 'dial %s %s\\n' "$2" "$3"
    ;;
  *) exit 98 ;;
esac
''')
            cli.chmod(0o700)
            for name in ("mac-home", "yogabook", "t480"):
                config = Path(temp) / f"{name}-config"
                config.write_text(self.hosts[name]["sshConfig"])
                proxy = directives(run(ssh, "-G", "-F", str(config), "mac-home").stdout).get("proxycommand", "")
                self.assertTrue(proxy, "no proxy configured")
                command = re.sub(r"/nix/store/[^\s'\"]+/bin/tailscale", str(cli), proxy)
                command = command.replace("%h", "mac-home").replace("%p", "22")
                argv = shlex.split(command)
                if argv[0].endswith(("/bin/bash", "/bin/sh")):
                    # Exercise Linux-generated POSIX logic on the macOS host,
                    # not a Linux interpreter binary that cannot run here.
                    argv[0] = "/bin/sh"
                # Also cover disappearance after IP lookup but before dial:
                # propagate failure, don't retry a hostname/direct connection.
                for present in ("yes", "no", "removed"):
                    with self.subTest(source=name, peer=present):
                        result = subprocess.run(
                            argv, capture_output=True, text=True,
                            env={**os.environ, "PEER_PRESENT": present}, timeout=10,
                        )
                        if present == "yes":
                            self.assertEqual(result.returncode, 0, result.stderr)
                            self.assertEqual(result.stdout, "dial 100.100.1.2 22\n")
                        else:
                            self.assertNotEqual(result.returncode, 0)
                            self.assertEqual(result.stdout, "")

    def test_sshd_parses_key_only_authentication_for_both_address_families(self):
        sshd = shutil.which("sshd") or ("/usr/sbin/sshd" if Path("/usr/sbin/sshd").exists() else None)
        keygen = shutil.which("ssh-keygen")
        if not sshd or not keygen:
            self.skipTest("OpenSSH daemon/keygen unavailable")
        with tempfile.TemporaryDirectory(prefix="sshd-fixture-", dir=ARTIFACTS) as temp:
            key = Path(temp) / "host_key"
            run(keygen, "-q", "-t", "ed25519", "-N", "", "-f", str(key))
            for name in ("mac-home", "yogabook", "t480"):
                host = self.hosts[name]
                if name == "mac-home":
                    text = host["sshExtraConfig"]
                else:
                    # Parse our evaluated directives with the native daemon;
                    # distribution-specific PAM paths are not a macOS fixture.
                    keys = ("PasswordAuthentication", "KbdInteractiveAuthentication", "PermitRootLogin", "AuthenticationMethods", "AllowUsers")
                    lines = []
                    for option in keys:
                        value = host["sshSettings"].get(option)
                        if value is None:
                            continue
                        if isinstance(value, bool):
                            value = "yes" if value else "no"
                        elif isinstance(value, list):
                            value = " ".join(value)
                        lines.append(f"{option} {value}")
                    text = "\n".join(lines)
                config = Path(temp) / f"{name}-sshd_config"
                config.write_text(f"HostKey {key}\n" + text + "\n")
                for address in ("100.100.1.2", "fd7a:115c:a1e0::123", "192.168.1.2"):
                    with self.subTest(host=name, address=address):
                        parsed = directives(run(sshd, "-T", "-f", str(config), "-C", f"user=gentooway,addr={address},host=fixture").stdout)
                        self.assertEqual(parsed["passwordauthentication"], "no")
                        self.assertEqual(parsed["kbdinteractiveauthentication"], "no")
                        self.assertEqual(parsed["permitrootlogin"], "no")
                        self.assertEqual(parsed["authenticationmethods"], "publickey")
                        # -T validates/prints AllowUsers, not actual CIDR-based
                        # admission; live denial is an explicit rollout check.
                        self.assertEqual(parsed["allowusers"].split(), ALLOW_USERS)


class SnapshotSelection(unittest.TestCase):
    def test_unreviewed_untracked_files_never_enter_source_manifest(self):
        ARTIFACTS.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="source-fixture-", dir=ARTIFACTS) as temp:
            root = Path(temp)
            run("git", "init", "--quiet", str(root))
            (root / "tracked.nix").write_text("{}\n")
            run("git", "-C", str(root), "add", "tracked.nix")
            # Non-sensitive fixture markers, not actual user data or keys.
            (root / "unreviewed.txt").write_text("untracked fixture marker\n")
            (root / "darwin").mkdir()
            (root / "darwin/remote-access.nix").write_text("{}\n")
            self.assertEqual(run("git", "-C", str(root), "ls-files", "--cached").stdout, "tracked.nix\n")
            entries = source_entries(root)
            self.assertIn("tracked.nix", entries)
            self.assertIn("darwin/remote-access.nix", entries)
            self.assertNotIn("unreviewed.txt", entries)


if __name__ == "__main__":
    unittest.main()
