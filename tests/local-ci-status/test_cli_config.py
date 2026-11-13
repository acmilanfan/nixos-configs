import json
import os
import subprocess
import sys
import unittest
from contextlib import redirect_stdout, redirect_stderr
from io import StringIO
from unittest.mock import patch

from support import NOW, SOURCE, UID, fixture, run, write_run
from observer import StateStore
from test_presentation import cli_module


class Config(unittest.TestCase):
    def observe(self, config, capture):
        cli = cli_module()
        original = cli.dispatch
        output, errors = StringIO(), StringIO()
        with patch.object(cli, 'dispatch', side_effect=lambda cfg, cmd, key=None:
                          original(cfg, cmd, key=key, now_ms=NOW, runner=capture)), \
                redirect_stdout(output), redirect_stderr(errors):
            code = cli.main(['--config', str(config), 'observe'])
        return code, output.getvalue(), errors.getvalue()

    def test_observe_reports_compact_idle_active_and_terminal_counts_after_saved_claims(self):
        for status, count in [('idle', 0), ('running', 1), ('passed', 0)]:
            with self.subTest(status=status):
                root = fixture()
                marker = root / 'enabled'
                marker.touch()
                config = root / 'config.json'
                config.write_text(json.dumps({'enabledFile': str(marker), 'stateDir': str(root / 'cache'), 'sharedRoot': str(root)}))
                item = run(label='fixture-private-label')
                if status == 'passed':
                    item |= {'status': 'passed', 'finishedAt': NOW, 'updatedAt': NOW}
                if status != 'idle':
                    write_run(root, item)
                calls = []
                def capture(argv, **kwargs):
                    if argv[0] == '/usr/bin/osascript':
                        with StateStore(root / 'cache') as store:
                            state = store.load()
                        self.assertTrue(state['seen'][f'{UID}:{item["runId"]}']['start'])
                        if status == 'passed':
                            self.assertTrue(state['seen'][f'{UID}:{item["runId"]}']['result'])
                    calls.append(argv)
                    return subprocess.CompletedProcess(argv, 0)
                code, output, errors = self.observe(config, capture)
                self.assertEqual(code, 0)
                self.assertEqual(json.loads(output), {'activeCount': count})
                self.assertNotIn('fixture-private-label', output)
                self.assertEqual(errors, '')
                self.assertTrue(any(c[0] == 'sketchybar' for c in calls))

    def test_observe_disabled_has_zero_activity_without_cache_or_gui(self):
        root = fixture()
        config = root / 'config.json'
        config.write_text(json.dumps({'enabledFile': str(root / 'absent'), 'stateDir': str(root / 'cache')}))
        def forbidden(*args, **kwargs):
            self.fail('disabled observe called GUI')
        code, output, errors = self.observe(config, forbidden)
        self.assertEqual((code, json.loads(output), errors), (0, {'activeCount': 0}, ''))
        self.assertFalse((root / 'cache').exists())

    def test_observe_failure_does_not_emit_a_successful_idle_summary(self):
        root = fixture()
        marker = root / 'enabled'
        marker.touch()
        cache = root / 'cache'
        cache.mkdir(mode=0o700)
        (cache / 'state.json').write_text('{')
        (cache / 'state.json').chmod(0o600)
        config = root / 'config.json'
        config.write_text(json.dumps({'enabledFile': str(marker), 'stateDir': str(cache), 'sharedRoot': str(root)}))
        code, output, errors = self.observe(config, lambda *a, **k: self.fail('invalid state reached GUI'))
        self.assertEqual(code, 0)  # CLI reporting remains advisory.
        self.assertEqual(output, '')
        self.assertIn('observer unavailable', errors)

    def test_interval_reads_config_without_claims_or_gui_dispatch(self):
        root = fixture()
        config = root / 'config.json'
        config.write_text(json.dumps({'interval': 5, 'stateDir': str(root / 'unused')}))
        result = subprocess.run([sys.executable, str(SOURCE / '__main__.py'), '--config', str(config), 'interval'],
                                capture_output=True, text=True, timeout=5,
                                env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), '5')
        self.assertFalse((root / 'unused').exists())
