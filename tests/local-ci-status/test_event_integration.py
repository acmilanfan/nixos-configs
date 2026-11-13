"""Actual observer JSON feeds the real Lua controller through fake GUI/time/IO."""
from contextlib import redirect_stdout
from io import StringIO
import json
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

from support import NOW, SOURCE, fixture, run, write_run
from test_presentation import cli_module


@unittest.skipUnless(os.environ.get('LOCAL_CI_LUA'), 'set LOCAL_CI_LUA to the locked Lua binary')
class EventIntegration(unittest.TestCase):
    def test_actual_observe_summaries_drive_event_and_timer_lifecycle_without_repeated_alerts(self):
        root = fixture()
        marker = root / 'enabled'
        marker.touch()
        config = root / 'config.json'
        config.write_text(json.dumps({'enabledFile': str(marker), 'stateDir': str(root / 'cache'), 'sharedRoot': str(root)}))
        calls, summaries = [], []
        cli = cli_module()
        dispatch = cli.dispatch
        def gui(argv, **kwargs):
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 0)
        def observe():
            output = StringIO()
            with patch.object(cli, 'dispatch', side_effect=lambda c, cmd, key=None: dispatch(c, cmd, key=key, now_ms=NOW, runner=gui)), redirect_stdout(output):
                self.assertEqual(cli.main(['--config', str(config), 'observe']), 0)
            summaries.append(output.getvalue().strip())
        observe()
        item = run()
        write_run(root, item)
        observe()
        write_run(root, item | {'status': 'passed', 'finishedAt': NOW, 'updatedAt': NOW})
        observe()
        observe()
        self.assertEqual([json.loads(s) for s in summaries], [{'activeCount': 0}, {'activeCount': 1}, {'activeCount': 0}, {'activeCount': 0}])
        self.assertEqual(len([c for c in calls if c[0] == '/usr/bin/osascript']), 2)
        summary_file = root / 'summaries.jsonl'
        summary_file.write_text('\n'.join(summaries) + '\n')
        result = subprocess.run([os.environ['LOCAL_CI_LUA'], 'tests/local-ci-status/test_watcher.lua'],
                                cwd=SOURCE.parents[3], capture_output=True, text=True, timeout=10,
                                env=dict(os.environ, LOCAL_CI_OBSERVE_FIXTURE=str(summary_file), LOCAL_CI_WATCH_ROOT=str(root)))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('actual Python summary to watcher lifecycle passed', result.stdout)
