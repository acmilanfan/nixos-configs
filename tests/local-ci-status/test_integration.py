"""Actual Node publisher ABI; opt in with LOCAL_CI_E2E_CHECKOUT to its worktree."""
import json
import os
from pathlib import Path
import subprocess
import unittest

from support import UID, fixture
from test_presentation import cli_module


@unittest.skipUnless(os.environ.get('LOCAL_CI_E2E_CHECKOUT'), 'set LOCAL_CI_E2E_CHECKOUT for Node publisher integration')
class PublisherIntegration(unittest.TestCase):
    def test_actual_node_records_reconcile_cancellation_crash_late_finish_reload_and_ack(self):
        checkout = Path(os.environ['LOCAL_CI_E2E_CHECKOUT']).resolve()
        publisher = (checkout / 'scripts/lib/run-status.mjs').as_uri()
        root = fixture()
        marker = root / 'enabled'
        marker.touch()
        config = {'sharedRoot': str(root), 'stateDir': str(root / 'cache'), 'enabledFile': str(marker)}
        def node(body):
            source = f'import * as p from {json.dumps(publisher)}; const deps={{sharedRoot:{json.dumps(str(root))},enabled:true,warn(){{}}}};\n' + body
            result = subprocess.run(['nix', 'develop', '--command', 'node', '--input-type=module', '-e', source],
                                    cwd=checkout, capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr[-2000:])
            return result.stdout.strip()
        manual_id = node('''const manual=p.startRun({source:'manual',project:'stack',label:'E2E all',env:{TOKEN:'fixture-sensitive-value'}},deps);
const ci=p.startRun({source:'ci',project:'backend',runId:'ci-123',label:'race-tests',jobUrl:'https://gitlab.com/weekenduo/backend/-/jobs/123'},deps);
if(!manual||!ci)throw Error('publisher failed');
p.finishRun(ci,'canceled',deps);
console.log(manual.file.split('/').pop().slice(0,-5));''')
        payloads = [json.loads(p.read_text()) for p in (root / f'weekenduo-ci-status-{UID}').glob('*.json')]
        self.assertEqual(len(payloads), 2)
        self.assertNotIn('fixture-sensitive-value', json.dumps(payloads))
        now = max(r['updatedAt'] for r in payloads) + 1000
        calls = []
        def gui(argv, **kwargs):
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 0)
        def alerts():
            return [c for c in calls if c[0] == '/usr/bin/osascript']
        cli = cli_module()
        view = cli.dispatch(config, 'refresh', now_ms=now, runner=gui)
        self.assertEqual(view['count'], 1)
        self.assertEqual(view['status'], 'failed')
        self.assertEqual(view['recent'][0]['status'], 'canceled')
        self.assertEqual(len(alerts()), 3)
        calls.clear()
        view = cli_module().dispatch(config, 'refresh', now_ms=now + 15000, runner=gui)
        self.assertEqual(view['count'], 0)
        self.assertIn('interrupted', [r['status'] for r in view['recent']])
        self.assertEqual(len(alerts()), 1)
        node(f'p.finishExistingRun({json.dumps(manual_id)}, "failed", deps);')
        calls.clear()
        view = cli_module().dispatch(config, 'refresh', now_ms=now + 16000, runner=gui)
        self.assertEqual(len(alerts()), 0)
        self.assertIn('failed', [r['status'] for r in view['recent']])
        view = cli.dispatch(config, 'ack', now_ms=now + 17000, runner=gui)
        self.assertFalse(view['stickyFailure'])
        view = cli_module().dispatch(config, 'refresh', now_ms=now + 18000, runner=gui)
        self.assertEqual(view['status'], 'idle')
        self.assertEqual(len(alerts()), 0)
