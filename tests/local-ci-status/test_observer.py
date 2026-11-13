import json
import os
import subprocess
import sys
import unittest

from support import NOW, SOURCE, UID, alive, fixture, run, write_run
import observer


class Observer(unittest.TestCase):
    def test_missing_unknown_overflow_round_trips_and_does_not_realert_evicted_ids(self):
        state = {}
        batches = [[run() for _ in range(size)] for size in (256, 256, 1)]
        for batch in batches:
            view, state, _ = observer.refresh(batch, state, lambda r: None, NOW)
        self.assertLessEqual(len(state['seen']), 512)
        self.assertTrue(any(r['runKey'] == f'{UID}:{batches[-1][0]["runId"]}' for r in view['active']))
        self.assertTrue(all(r['status'] == 'unknown' for r in view['active']))
        self.assertFalse(view['recent'])  # Overflow must not fabricate terminal results.
        with observer.StateStore(fixture() / 'cache') as store:
            store.save(state)
            restored = store.load()
        evicted = next(r for batch in batches[:-1] for r in batch if f'{UID}:{r["runId"]}' not in restored['seen'])
        _, restored, notices = observer.refresh([evicted], restored, lambda r: None, NOW + 1000)
        self.assertEqual(notices, [])
        self.assertLessEqual(len(restored['seen']), 512)
        current = batches[-1][0] | {'status': 'passed', 'finishedAt': NOW + 2000, 'updatedAt': NOW + 2000}
        _, _, notices = observer.refresh([current], state, lambda r: None, NOW + 2000)
        self.assertEqual([n['event'] for n in notices], ['result'])

    def test_notifications_survive_reload_and_short_run_between_polls(self):
        item = run(status='passed', finishedAt=NOW + 1000, updatedAt=NOW + 1000)
        view, state, notices = observer.refresh([item], {}, alive, NOW + 2000)
        self.assertEqual([n['event'] for n in notices], ['start', 'result'])
        self.assertEqual(view['status'], 'passed')
        _, _, repeated = observer.refresh([item], json.loads(json.dumps(state)), alive, NOW + 3000)
        self.assertEqual(repeated, [])
        view, _, _ = observer.refresh([], state, alive, NOW + 31000)
        self.assertEqual(view['status'], 'idle')

    def test_old_history_is_silent_and_running_updates_do_not_repeat_start(self):
        old = run(status='passed', finishedAt=NOW, updatedAt=NOW)
        view, state, notices = observer.refresh([old], {}, alive, NOW + 61000)
        self.assertEqual(notices, [])
        self.assertEqual(len(view['recent']), 1)
        active = run()
        _, state, notices = observer.refresh([active], state, alive, NOW + 62000)
        self.assertEqual([n['event'] for n in notices], ['start'])
        view, _, notices = observer.refresh([active | {'label': 'full'}], state, alive, NOW + 65000)
        self.assertEqual(notices, [])
        self.assertEqual(view['active'][0]['elapsedSeconds'], 65)
        self.assertEqual(view['active'][0]['label'], 'full')

    def test_sticky_failure_survives_expiry_history_pruning_and_ack(self):
        failed = run(status='failed', finishedAt=NOW, updatedAt=NOW)
        active = run()
        view, state, _ = observer.refresh([failed, active], {}, alive, NOW)
        self.assertEqual(view['status'], 'failed')
        self.assertEqual(view['count'], 1)
        many = [run(status='passed', finishedAt=NOW + i, updatedAt=NOW + i) for i in range(600)]
        view, state, _ = observer.refresh(many, state, alive, NOW + 700000)
        self.assertTrue(state['stickyFailure'])
        self.assertLessEqual(len(state['seen']), 512)
        self.assertLessEqual(len(view['recent']), 20)
        state = observer.acknowledge(state)
        view, _, _ = observer.refresh([], state, alive, NOW + 800000)
        self.assertEqual(view['status'], 'running')  # missing record still has a live owner
        self.assertFalse(view['stickyFailure'])

    def test_dead_or_reused_pid_waits_fifteen_seconds_and_late_result_does_not_alert_twice(self):
        for lookup in (lambda r: False, lambda r: {'uid': UID, 'startedAt': 'different'}):
            item = run()
            view, state, _ = observer.refresh([item], {}, lookup, NOW)
            self.assertEqual(view['status'], 'running')
            view, state, notices = observer.refresh([item], state, lookup, NOW + 14999)
            self.assertEqual(notices, [])
            view, state, notices = observer.refresh([item], state, lookup, NOW + 15000)
            self.assertEqual(view['recent'][0]['status'], 'interrupted')
            self.assertEqual([n['event'] for n in notices], ['result'])
            late = item | {'status': 'canceled', 'finishedAt': NOW + 16000, 'updatedAt': NOW + 16000}
            view, state, notices = observer.refresh([late], state, lookup, NOW + 17000)
            self.assertEqual(view['recent'][0]['status'], 'canceled')
            self.assertEqual(notices, [])

    def test_unknown_is_not_dead_and_sleep_does_not_infer_success(self):
        item = run()
        _, state, _ = observer.refresh([item], {}, alive, NOW)
        view, state, notices = observer.refresh([item], state, lambda r: None, NOW + 86400000)
        self.assertEqual(view['active'][0]['status'], 'unknown')
        self.assertEqual(notices, [])
        view, _, _ = observer.refresh([item], state, alive, NOW + 86401000)
        self.assertEqual(view['status'], 'running')

    def test_concurrent_runs_have_independent_events(self):
        items = [run(), run()]
        view, state, notices = observer.refresh(items, {}, alive, NOW)
        self.assertEqual(view['count'], 2)
        self.assertEqual(len(notices), 2)
        items[0] |= {'status': 'passed', 'finishedAt': NOW + 1000, 'updatedAt': NOW + 1000}
        view, _, notices = observer.refresh(items, state, alive, NOW + 1000)
        self.assertEqual(view['count'], 1)
        self.assertEqual(view['status'], 'running')
        self.assertEqual(len(notices), 1)


class Cache(unittest.TestCase):
    def test_cli_lists_results_and_acknowledges_without_replaying_failure(self):
        root = fixture()
        now = __import__('time').time_ns() // 1000000
        item = run(status='failed', startedAt=now - 1000, finishedAt=now, updatedAt=now)
        write_run(root, item)
        config = root / 'config.json'
        marker = root / 'enabled'
        marker.touch()
        config.write_text(json.dumps({'sharedRoot': str(root), 'stateDir': str(root / 'cache'), 'enabledFile': str(marker)}))
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', PYTHONPATH=str(SOURCE))
        boundary = '''import subprocess,runpy,sys
original_run = subprocess.run
def gui_boundary(argv, **kwargs):
    if argv[0] in ('/usr/bin/open', '/usr/bin/osascript', 'sketchybar'):
        return subprocess.CompletedProcess(argv, 0)
    return original_run(argv, **kwargs)
subprocess.run = gui_boundary
sys.argv = sys.argv[1:]
runpy.run_path(sys.argv[0], run_name='__main__')
'''
        def cli(verb):
            result = subprocess.run([sys.executable, '-c', boundary, str(SOURCE / '__main__.py'), '--config', str(config), verb],
                                    capture_output=True, text=True, timeout=10, env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)
        self.assertEqual(cli('list')['status'], 'failed')
        result = subprocess.run([sys.executable, '-c', boundary, str(SOURCE / '__main__.py'), '--config', str(config), 'ack'],
                                capture_output=True, text=True, timeout=10, env=env)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(cli('list')['status'], 'idle')
        state = json.loads((root / 'cache/state.json').read_text())
        self.assertTrue(state['seen'][f'{UID}:{item["runId"]}']['result'])

    def test_private_cache_persists_claims_before_dispatch_and_serializes_workers(self):
        root = fixture()
        state_dir = root / 'cache'
        item = run()
        script = '''import json,sys
from observer import StateStore, refresh
with StateStore(sys.argv[1]) as store:
    view, state, notices = refresh([json.loads(sys.argv[2])], store.load(), lambda r: {'uid': r['ownerUid'], 'startedAt': r['ownerStartedAt']}, 2000000)
    store.save(state)
print(len(notices))
'''
        env = dict(os.environ, PYTHONPATH=str(SOURCE), PYTHONDONTWRITEBYTECODE='1')
        workers = [subprocess.Popen([sys.executable, '-c', script, str(state_dir), json.dumps(item)],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, text=True) for _ in range(6)]
        outputs = [p.communicate(timeout=10) for p in workers]
        self.assertTrue(all(p.returncode == 0 for p in workers), outputs)
        self.assertEqual(sum(int(out) for out, _ in outputs), 1)
        self.assertEqual(state_dir.stat().st_mode & 0o777, 0o700)
        self.assertEqual((state_dir / 'state.json').stat().st_mode & 0o777, 0o600)

    def test_unsafe_cache_roots_files_and_locks_are_rejected(self):
        for kind in ('root-link', 'root-mode', 'file-link', 'file-mode', 'lock-link', 'corrupt'):
            with self.subTest(kind=kind):
                root = fixture()
                cache = root / 'cache'
                cache.mkdir(mode=0o700)
                target = root / 'protected'
                target.write_text('protected')
                if kind == 'root-link':
                    cache.rmdir()
                    cache.symlink_to(root)
                elif kind == 'root-mode':
                    cache.chmod(0o755)
                elif kind in ('file-link', 'lock-link'):
                    (cache / ('state.json' if kind == 'file-link' else 'lock')).symlink_to(target)
                else:
                    state = cache / 'state.json'
                    state.write_text('{' if kind == 'corrupt' else '{}')
                    state.chmod(0o600 if kind == 'corrupt' else 0o644)
                with self.assertRaises((OSError, ValueError)):
                    with observer.StateStore(cache) as store:
                        store.load()
                self.assertEqual(target.read_text(), 'protected')
