"""Locked host evaluation only: never build/switch activation or run GUI services."""
import json
from pathlib import Path
import subprocess
import unittest

from support import ARTIFACTS, SOURCE, fixture

ROOT = SOURCE.parents[3]


class HostIsolation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.hosts = {}
        expression = '''c: let
          user = if c ? system && c.system ? primaryUser then c.system.primaryUser else "gentooway";
          home = c.home-manager.users.${user};
          cfg = home.services.localCiStatus or {};
          files = home.home.file;
          helpers = builtins.filter (p: (p.pname or p.name or "") == "local-ci-status") home.home.packages;
        in {
          enable = cfg.enable or false;
          helpers = map toString helpers;
          marker = files ? ".config/local-ci-status/enabled";
          config = files.".config/local-ci-status/config.json".text or null;
          plugin = files.".config/sketchybar/plugins/ci_status.sh".source or null;
          pluginExecutable = files.".config/sketchybar/plugins/ci_status.sh".executable or null;
          failedAssertions = map (a: a.message) (builtins.filter (a: !a.assertion) c.assertions);
        }'''
        for host, output in [('mac-home', 'darwinConfigurations'), ('mac-work', 'darwinConfigurations'),
                             ('t480-home', 'nixosConfigurations')]:
            result = subprocess.run(['nix', 'eval', '--json', '--no-write-lock-file',
                                     f'.#{output}.{host}.config', '--apply', expression],
                                    cwd=ROOT, capture_output=True, text=True, timeout=120)
            if result.returncode:
                raise AssertionError(f'{host}: {result.stderr[-3000:]}')
            cls.hosts[host] = json.loads(result.stdout)
        (ARTIFACTS.parent / 'task-5-hosts.json').write_text(json.dumps(cls.hosts, indent=2) + '\n')

    def test_only_mac_home_has_the_helper_marker_config_and_plugin(self):
        for host, value in self.hosts.items():
            with self.subTest(host=host):
                enabled = host == 'mac-home'
                self.assertEqual(value['enable'], enabled)
                self.assertEqual(len(value['helpers']), 1 if enabled else 0)
                self.assertEqual(value['marker'], enabled)
                self.assertEqual(value['config'] is not None, enabled)
                self.assertEqual(value['plugin'] is not None, enabled)
                self.assertEqual(value['failedAssertions'], [])
        self.assertTrue(self.hosts['mac-home']['pluginExecutable'])

    def test_generated_config_contains_only_nonsecret_runtime_contract(self):
        config = json.loads(self.hosts['mac-home']['config'] or '{}')
        self.assertEqual(config.get('ciUser'), 'weekenduo-ci')
        self.assertEqual(config.get('interval'), 3)
        self.assertEqual(config.get('finalizationGraceSeconds'), 15)
        self.assertEqual(config.get('successSeconds'), 30)
        self.assertEqual(config.get('sharedRoot'), '/Users/Shared')
        self.assertEqual(config.get('allowedProjects'), ['weekenduo/backend', 'weekenduo/duomobile'])
        self.assertNotIn('TOKEN', json.dumps(config))
        self.assertNotIn('environment', config)

    def test_built_helper_and_generated_config_work_without_shell_initialization(self):
        result = subprocess.run(['nix', 'build', '--no-link', '--no-write-lock-file',
                                 '.#darwinConfigurations.mac-home.config.home-manager.users.gentooway.services.localCiStatus.package'],
                                cwd=ROOT, capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stderr[-2000:])
        binary = str(Path(self.hosts['mac-home']['helpers'][0]) / 'bin/local-ci-status')
        root = fixture()
        config = root / 'config.json'
        config.write_text(self.hosts['mac-home']['config'])
        # interval does not touch the desktop, shared records or cache.
        result = subprocess.run([binary, '--config', str(config), 'interval'],
                                capture_output=True, text=True, timeout=10,
                                env={'HOME': str(root), 'PATH': '/usr/bin:/bin'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), '3')
        config.write_text(json.dumps({'enabledFile': str(root / 'absent'), 'stateDir': str(root / 'cache')}))
        result = subprocess.run([binary, '--config', str(config), 'list'],
                                capture_output=True, text=True, timeout=10,
                                env={'HOME': str(root), 'PATH': '/usr/bin:/bin'})
        self.assertEqual(result.stdout.strip(), '{}')
        self.assertFalse((root / 'cache').exists())
