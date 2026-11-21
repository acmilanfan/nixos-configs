"""Evaluate the Linux CI runner module and exercise its helpers; never activate."""
import json
import os
import stat
import subprocess
import tempfile
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "nixos/common/ci-runner/scripts"


def evaluate(host, expression, extend=""):
    source = (
        f'let f = builtins.getFlake "{ROOT}"; lib = f.inputs.nixpkgs.lib; '
        f"h = f.nixosConfigurations.{host}{extend}; "
        f"in let config = h.config; in {expression}"
    )
    result = subprocess.run(
        ["nix", "eval", "--json", "--no-write-lock-file", "--impure", "--expr", source],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=300,
    )
    if result.returncode:
        raise AssertionError(result.stderr[-5000:])
    return json.loads(result.stdout)


def enabled(host, expression):
    return evaluate(
        host,
        expression,
        ".extendModules { modules = [ { services.weekenduoCi.enable = lib.mkForce true; } ]; }",
    )


def disabled(host, expression):
    return evaluate(
        host,
        expression,
        ".extendModules { modules = [ { services.weekenduoCi.enable = lib.mkForce false; } ]; }",
    )


MODULE_EXPRESSION = """let
  user = config.users.users.weekenduo-ci;
  docker = config.virtualisation.docker;
  service = config.systemd.services.weekenduo-ci-runner;
  logind = config.services.logind.settings.Login;
in {
  hasOption = config.services ? weekenduoCi;
  user = {
    uid = user.uid;
    home = toString user.home;
    createHome = user.createHome;
    shell = toString user.shell;
    extraGroups = user.extraGroups;
    packages = map (p: { name = p.pname or p.name or ""; version = p.version or ""; }) user.packages;
  };
  docker = {
    enable = docker.enable;
    dataRoot = docker.daemon.settings."data-root" or null;
    requiresMountsFor = config.systemd.services.docker.unitConfig.RequiresMountsFor or [ ];
  };
  service = {
    user = service.serviceConfig.User or null;
    group = service.serviceConfig.Group or null;
    runtimeDirectory = service.serviceConfig.RuntimeDirectory or null;
    loadCredential = service.serviceConfig.LoadCredential or [ ];
    execStartPre = service.serviceConfig.ExecStartPre or "";
    execStart = service.serviceConfig.ExecStart or "";
    timeoutStopSec = service.serviceConfig.TimeoutStopSec or null;
    environment = service.environment;
  };
  nixLd = config.programs.nix-ld.enable;
  template = config.services.weekenduoCi.runnerConfigTemplate;
  logind = {
    handleLidSwitch = logind.HandleLidSwitch or null;
    handleLidSwitchExternalPower = logind.HandleLidSwitchExternalPower or null;
    idleAction = logind.IdleAction or null;
  };
  failed = map (a: a.message) (builtins.filter (a: !a.assertion) config.assertions);
}"""


class ModuleContract(unittest.TestCase):
    def packages(self, value):
        return {p["name"]: p["version"] for p in value["user"]["packages"]}

    def test_artifact_path_is_provisioned_for_runner(self):
        rules = enabled("yogabook-gen10", "config.systemd.tmpfiles.rules")
        directories = {
            fields[1]: fields[2:5]
            for rule in rules
            if (fields := rule.split()) and fields[0] == "d"
        }
        for path in ("/home/weekenduo-ci/ai", "/home/weekenduo-ci/ai/artifacts"):
            with self.subTest(path=path):
                self.assertEqual(directories.get(path), ["0700", "weekenduo-ci", "weekenduo-ci"])

    def test_yogabook_contract(self):
        value = enabled("yogabook-gen10", MODULE_EXPRESSION)
        self.assertTrue(value["hasOption"])
        self.assertTrue(value["nixLd"])
        self.assertEqual(value["service"]["environment"]["NIX_LD"],
                         "/run/current-system/sw/share/nix-ld/lib/ld.so")
        self.assertEqual(value["service"]["environment"]["NIX_LD_LIBRARY_PATH"],
                         "/run/current-system/sw/share/nix-ld/lib")
        user = value["user"]
        self.assertEqual(user["uid"], 599)
        self.assertEqual(user["home"], "/home/weekenduo-ci")
        self.assertTrue(user["createHome"])
        self.assertTrue(user["shell"].endswith("/bash"), user["shell"])
        self.assertIn("docker", user["extraGroups"])
        packages = self.packages(value)
        self.assertIn("nodejs", packages)
        self.assertTrue(packages["nodejs"].startswith("22."), packages["nodejs"])
        self.assertIn("go", packages)
        self.assertTrue("gcc" in packages or "gcc-wrapper" in packages, packages)
        self.assertIn("gitlab-runner", packages)
        self.assertIn("iproute2", packages)
        self.assertIn("lsof", packages)
        self.assertTrue("docker" in packages or "docker-client" in packages, packages)
        self.assertIn("xvfb", packages)
        self.assertEqual(packages["cypress"], "13.17.0")

        self.assertTrue(value["docker"]["enable"])
        self.assertEqual(value["docker"]["dataRoot"], "/home/docker")
        self.assertIn("/home", value["docker"]["requiresMountsFor"])

        service = value["service"]
        self.assertEqual(service["user"], "weekenduo-ci")
        self.assertEqual(service["group"], "weekenduo-ci")
        self.assertEqual(service["runtimeDirectory"], "weekenduo-ci")
        self.assertIn("runner-env:/etc/weekenduo-ci/runner.env", service["loadCredential"])
        self.assertIn("weekenduo-ci-prepare", service["execStartPre"])
        self.assertIn("gitlab-runner run --config /run/weekenduo-ci/config.toml", service["execStart"])
        self.assertEqual(service["timeoutStopSec"], "7min")

        parsed = tomllib.loads(value["template"])
        self.assertEqual(parsed["concurrent"], 2)
        self.assertEqual(parsed["shutdown_timeout"], 420)
        self.assertEqual(len(parsed["runners"]), 2)
        for runner in parsed["runners"]:
            self.assertTrue(runner["token"].startswith("__"), runner["token"])
            self.assertEqual(runner["executor"], "shell")
            self.assertEqual(runner["builds_dir"], "/home/weekenduo-ci/ci-builds")
            self.assertEqual(runner["request_concurrency"], 2)
            self.assertIn("DOCKER_HOST=unix:///var/run/docker.sock", runner["environment"])
            self.assertIn("CYPRESS_INSTALL_BINARY=0", runner["environment"])
            self.assertIn("CYPRESS_RUN_BINARY=", " ".join(runner["environment"]))
            self.assertIn("NIX_LD=/run/current-system/sw/share/nix-ld/lib/ld.so", runner["environment"])
            self.assertIn("NIX_LD_LIBRARY_PATH=/run/current-system/sw/share/nix-ld/lib", runner["environment"])
            self.assertIn("WD_CI_STATUS_ENABLE=0", runner["environment"])
            self.assertIn("weekenduo-ci-pre-build", runner["pre_build_script"])
            self.assertIn("weekenduo-ci-post-build", runner["post_build_script"])
        self.assertNotIn("glrt-", value["template"])
        self.assertNotEqual(value["logind"]["handleLidSwitch"], "ignore")
        self.assertEqual(value["failed"], [])

    def test_t480_contract(self):
        value = enabled("t480-home", MODULE_EXPRESSION)
        self.assertEqual(tomllib.loads(value["template"])["concurrent"], 1)
        self.assertEqual(value["logind"]["handleLidSwitch"], "ignore")
        self.assertEqual(value["logind"]["handleLidSwitchExternalPower"], "ignore")
        self.assertEqual(value["logind"]["idleAction"], "ignore")
        self.assertEqual(value["failed"], [])

    def test_disabled_host_has_no_runner_account(self):
        value = disabled("vm-hyprland", """{
          hasOption = config.services ? weekenduoCi;
          hasUser = config.users.users ? weekenduo-ci;
          hasService = config.systemd.services ? weekenduo-ci-runner;
          failed = map (a: a.message) (builtins.filter (a: !a.assertion) config.assertions);
        }""")
        self.assertTrue(value["hasOption"])
        self.assertFalse(value["hasUser"])
        self.assertFalse(value["hasService"])
        self.assertEqual(value["failed"], [])


class HelperScripts(unittest.TestCase):
    def run_script(self, name, args, env=None):
        return subprocess.run(
            ["bash", str(SCRIPTS / name), *args],
            capture_output=True,
            text=True,
            env=env,
            timeout=30,
        )

    def test_set_tokens_syntax_and_root_guard(self):
        syntax = subprocess.run(
            ["bash", "-n", str(SCRIPTS / "set-tokens.sh")],
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(syntax.returncode, 0, syntax.stderr)
        result = self.run_script("set-tokens.sh", [])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sudo", result.stderr)

    def test_prepare_requires_both_tokens_and_writes_mode_0600(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            template = root / "template.toml"
            template.write_text(
                'concurrent = 2\n[[runners]]\n  token = "__BACKEND_TOKEN__"\n'
                '[[runners]]\n  token = "__FRONTEND_TOKEN__"\n'
            )
            cred = root / "cred"
            cred.mkdir()
            legacy_backend = "glrt-abcdefghijklmnopqrst"
            routable_frontend = "glrt-abcdefghijklmnopqrstuvwxyz0.01.ab1234567"
            (cred / "runner-env").write_text(
                f"BACKEND_TOKEN={legacy_backend}\nFRONTEND_TOKEN={routable_frontend}\n"
            )
            output = root / "run/config.toml"
            env = {**os.environ, "CREDENTIALS_DIRECTORY": str(cred)}
            result = self.run_script("prepare.sh", [str(template), str(output)], env)
            self.assertEqual(result.returncode, 0, result.stderr)
            text = output.read_text()
            self.assertIn(legacy_backend, text)
            self.assertIn(routable_frontend, text)
            self.assertNotIn("glrt-", result.stdout + result.stderr)
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)

            (cred / "runner-env").write_text(f"BACKEND_TOKEN={legacy_backend}\n")
            missing = root / "missing/config.toml"
            result = self.run_script("prepare.sh", [str(template), str(missing)], env)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(missing.exists())

            (cred / "runner-env").write_text("BACKEND_TOKEN=not-a-runner-token\nFRONTEND_TOKEN=glrt-ok\n")
            malformed = root / "malformed/config.toml"
            result = self.run_script("prepare.sh", [str(template), str(malformed)], env)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(malformed.exists())

    def test_disk_guard(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(self.run_script("disk-guard.sh", [tmp, "0"]).returncode, 0)
            result = self.run_script("disk-guard.sh", [tmp, "999999"])
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("disk guard", result.stderr)

    def test_power_guard(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ac = root / "AC"
            ac.mkdir()
            (ac / "online").write_text("1\n")
            env = {**os.environ, "WEEKENDUO_CI_POWER_SUPPLY": str(root)}
            self.assertEqual(self.run_script("power-guard.sh", ["30"], env).returncode, 0)

            (ac / "online").write_text("0\n")
            battery = root / "BAT0"
            battery.mkdir()
            (battery / "capacity").write_text("10\n")
            result = self.run_script("power-guard.sh", ["30"], env)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("battery", result.stderr)

            (battery / "capacity").unlink()
            battery.rmdir()
            self.assertEqual(self.run_script("power-guard.sh", ["30"], env).returncode, 0)

    def test_record_docker_writes_pinned_policy(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bindir = root / "bin"
            bindir.mkdir()
            docker = bindir / "docker"
            docker.write_text("#!/bin/sh\nprintf '123e4567-e89b-12d3-a456-426614174000\\n'\n")
            docker.chmod(0o700)
            id_command = bindir / "id"
            id_command.write_text("#!/bin/sh\nprintf 'weekenduo-ci\\n'\n")
            id_command.chmod(0o700)
            env = {**os.environ, "HOME": str(root), "PATH": f"{bindir}:{os.environ['PATH']}"}
            result = self.run_script("record-docker.sh", [], env)
            self.assertEqual(result.returncode, 0, result.stderr)
            policy_path = root / ".config/weekenduo-ci/runtime.json"
            policy = json.loads(policy_path.read_text())
            self.assertEqual(policy["user"], "weekenduo-ci")
            self.assertEqual(policy["home"], str(root))
            self.assertEqual(policy["dockerSocket"], "/var/run/docker.sock")
            self.assertEqual(policy["dockerId"], "123e4567-e89b-12d3-a456-426614174000")
            self.assertEqual(policy["buildRoot"], f"{root}/ci-builds")
            self.assertEqual(policy["artifactRoot"], f"{root}/ai/artifacts")
            self.assertEqual(stat.S_IMODE(policy_path.stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
