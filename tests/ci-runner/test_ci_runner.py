"""Evaluate the Nix-managed headless CI user and daemon; never activate."""
import json
from pathlib import Path
import subprocess
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[2]
AGE_RECIPIENT = 'age1m2j9773er9hwv2twsfe8a5fwfc4ya0ex56cpsrk8jrfjgduy4fcs3c0gla'


def evaluate(host, expression, extend=''):
    flake = str(ROOT)
    source = (f'let f = builtins.getFlake "{flake}"; lib = f.inputs.nixpkgs.lib; '
              f'h = f.darwinConfigurations.{host}{extend}; '
              f'in let config = h.config; in {expression}')
    result = subprocess.run(['nix', 'eval', '--json', '--no-write-lock-file', '--impure',
                             '--expr', source], cwd=ROOT, capture_output=True, text=True, timeout=180)
    if result.returncode:
        raise AssertionError(result.stderr[-5000:])
    return json.loads(result.stdout)


def enabled(expression):
    return evaluate('mac-home', expression,
                    '.extendModules { modules = [ { services.ciRunner.enable = lib.mkForce true; } ]; }')


def disabled(expression):
    return evaluate('mac-home', expression,
                    '.extendModules { modules = [ { services.ciRunner.enable = lib.mkForce false; } ]; }')


def user_expression():
    return '''let
      user = config.users.users.weekenduo-ci;
    in {
      uid = user.uid;
      home = toString user.home;
      createHome = user.createHome;
      isHidden = user.isHidden;
      shell = toString user.shell;
      packages = map (p: { name = p.pname or p.name or ""; version = p.version or ""; }) user.packages;
      known = config.users.knownUsers;
      hasHmUser = config.home-manager.users ? weekenduo-ci;
      hasDaemon = config.launchd.daemons ? "local.weekenduo-ci-runner";
      failed = map (a: a.message) (builtins.filter (a: !a.assertion) config.assertions);
    }'''


class HostIsolation(unittest.TestCase):
    def test_account_is_managed_but_runner_is_disabled_by_default(self):
        value = disabled(user_expression())
        self.assertEqual(value['uid'], 599)
        self.assertEqual(value['home'], '/Users/weekenduo-ci')
        self.assertTrue(value['createHome'])
        self.assertTrue(value['isHidden'])
        self.assertEqual(value['shell'], '/bin/bash')
        self.assertIn('weekenduo-ci', value['known'])
        self.assertFalse(value['hasHmUser'])
        self.assertFalse(value['hasDaemon'])
        self.assertEqual(value['failed'], [])
        packages = {p['name']: p['version'] for p in value['packages']}
        self.assertIn('nodejs', packages)
        self.assertIn('go', packages)
        self.assertIn('gitlab-runner', packages)
        work = evaluate('mac-work', '''{
          hasOption = config.services ? ciRunner;
          hasUser = config.users.users ? weekenduo-ci;
          failed = map (a: a.message) (builtins.filter (a: !a.assertion) config.assertions);
        }''')
        self.assertFalse(work['hasOption'])
        self.assertFalse(work['hasUser'])
        self.assertEqual(work['failed'], [])

    def test_enabled_daemon_profile_and_sops_contract(self):
        value = enabled('''let
          user = config.users.users.weekenduo-ci;
          daemon = config.launchd.daemons."local.weekenduo-ci-runner";
          configDaemon = config.launchd.daemons."local.weekenduo-ci-config";
          template = config.sops.templates."gitlab-runner-config";
        in {
          user = {
            inherit (user) uid createHome isHidden;
            home = toString user.home;
            shell = toString user.shell;
            packages = map (p: { name = p.pname or p.name or ""; version = p.version or ""; }) user.packages;
          };
          known = config.users.knownUsers;
          hasHmUser = config.home-manager.users ? weekenduo-ci;
          daemon = {
            script = daemon.script;
            environment = daemon.environment;
            serviceConfig = {
              inherit (daemon.serviceConfig) UserName GroupName RunAtLoad KeepAlive
                WorkingDirectory StandardOutPath StandardErrorPath ProcessType ThrottleInterval;
            };
          };
          configDaemon = {
            script = configDaemon.script;
            serviceConfig = { inherit (configDaemon.serviceConfig) RunAtLoad KeepAlive WatchPaths; };
          };
          template = { inherit (template) path owner mode content; };
          secrets = builtins.attrNames config.sops.secrets;
          ageKey = config.sops.age.keyFile;
          agePaths = config.sops.age.sshKeyPaths;
          ageSshKey = config.sops.age.sshKeyFile;
          gpgHostKeys = config.sops.gnupg.sshKeyPaths;
          postActivation = config.system.activationScripts.postActivation.text;
          failed = map (a: a.message) (builtins.filter (a: !a.assertion) config.assertions);
        }''')
        user = value['user']
        self.assertEqual(user['uid'], 599)
        self.assertEqual(user['home'], '/Users/weekenduo-ci')
        self.assertTrue(user['createHome'])
        self.assertTrue(user['isHidden'])
        self.assertEqual(user['shell'], '/bin/bash')
        packages = {p['name']: p['version'] for p in user['packages']}
        self.assertIn('gitlab-runner', packages)
        self.assertIn('nodejs', packages)
        self.assertTrue(packages['nodejs'].startswith('22.'), packages['nodejs'])
        self.assertIn('go', packages)
        self.assertIn('git', packages)
        self.assertIn('curl', packages)
        self.assertIn('docker', packages)
        self.assertIn('colima', packages)
        self.assertIn('weekenduo-ci', value['known'])
        self.assertFalse(value['hasHmUser'])
        self.assertEqual(value['failed'], [])
        daemon = value['daemon']
        self.assertTrue(daemon['script'].strip().endswith('gitlab-runner run --config /Users/weekenduo-ci/.gitlab-runner/config.toml'))
        self.assertEqual(daemon['environment']['HOME'], '/Users/weekenduo-ci')
        self.assertIn('/etc/profiles/per-user/weekenduo-ci/bin', daemon['environment']['PATH'])
        config = daemon['serviceConfig']
        self.assertEqual(config['UserName'], 'weekenduo-ci')
        self.assertEqual(config['GroupName'], 'staff')
        self.assertTrue(config['RunAtLoad'])
        self.assertTrue(config['KeepAlive'])
        self.assertEqual(config['WorkingDirectory'], '/Users/weekenduo-ci')
        self.assertEqual(config['StandardOutPath'], '/Users/weekenduo-ci/Library/Logs/gitlab-runner.log')
        self.assertEqual(config['StandardErrorPath'], '/Users/weekenduo-ci/Library/Logs/gitlab-runner.error.log')
        self.assertEqual(config['ProcessType'], 'Background')
        self.assertEqual(config['ThrottleInterval'], 10)
        copy = value['configDaemon']
        self.assertIn('/run/secrets/rendered/gitlab-runner-config', copy['script'])
        self.assertIn('/Users/weekenduo-ci/.gitlab-runner/config.toml', copy['script'])
        self.assertIn('kickstart -k system/org.nixos.local.weekenduo-ci-runner', copy['script'])
        self.assertTrue(copy['serviceConfig']['RunAtLoad'])
        self.assertFalse(copy['serviceConfig']['KeepAlive'])
        self.assertEqual(copy['serviceConfig']['WatchPaths'], ['/run/secrets.d'])
        template = value['template']
        self.assertEqual(template['path'], '/Users/weekenduo-ci/.gitlab-runner/config.toml')
        self.assertEqual(template['owner'], 'weekenduo-ci')
        self.assertEqual(template['mode'], '0600')
        self.assertNotIn('glrt-', template['content'])
        parsed = tomllib.loads(template['content'])
        self.assertEqual(parsed['concurrent'], 2)
        self.assertEqual(len(parsed['runners']), 2)
        for runner in parsed['runners']:
            self.assertTrue(runner['token'].startswith('<SOPS:'))
            self.assertEqual(runner['executor'], 'shell')
            self.assertEqual(runner['builds_dir'], '/Users/weekenduo-ci/ci-builds')
            env = runner['environment']
            self.assertTrue(any(item.startswith('PATH=/etc/profiles/per-user/weekenduo-ci/bin') for item in env))
            self.assertIn('DOCKER_HOST=unix:///Users/weekenduo-ci/.colima/default/docker.sock', env)
            self.assertIn('WD_CI_STATUS_ENABLE=1', env)
            pre = runner['pre_build_script']
            self.assertIn('colima status', pre)
            self.assertIn('colima start --cpu 6 --memory 12 --disk 60 --activate=false', pre)
            self.assertIn('DOCKER_HOST=unix:///Users/weekenduo-ci/.colima/default/docker.sock', pre)
            self.assertNotIn('/Users/gentooway/.colima', pre)
        self.assertIn('gitlab_runner/backend_token', value['secrets'])
        self.assertIn('gitlab_runner/frontend_token', value['secrets'])
        self.assertEqual(value['ageKey'], '/var/lib/sops-nix/age.key')
        self.assertIsNone(value['ageSshKey'])
        self.assertEqual(value['agePaths'], [])
        self.assertEqual(value['gpgHostKeys'], [])
        self.assertIn('ssh-to-age -private-key', value['postActivation'])
        self.assertLess(value['postActivation'].index('ssh-to-age -private-key'),
                        value['postActivation'].index('sops-install-secrets'))
        self.assertIn('install -d', value['postActivation'])
        self.assertIn('.metadata_never_index', value['postActivation'])
        self.assertIn('/Users/weekenduo-ci/.gitlab-runner', value['postActivation'])
        self.assertLess(value['postActivation'].index('install -d'),
                        value['postActivation'].index('sops-install-secrets'))
        self.assertIn(AGE_RECIPIENT, (ROOT / '.sops.yaml').read_text())

    def test_disabled_rebuild_removes_only_the_old_user_agent(self):
        value = disabled('config.system.activationScripts.postActivation.text')
        self.assertIn('org.nixos.local.weekenduo-ci-runner', value)
        self.assertIn('org.nixos.local.weekenduo-ci-config', value)
        self.assertIn('bootout', value)
