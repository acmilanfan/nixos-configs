"""Desktop-owned reconciliation and notification claims. No GUI side effects."""
import copy
import fcntl
import json
import os
from pathlib import Path
import uuid

from records import NOFOLLOW, TERMINAL, checked, read_json


def run_key(run):
    return f'{run["ownerUid"]}:{run["runId"]}'


def acknowledge(state):
    state = copy.deepcopy(state)
    state['stickyFailure'] = False
    return state


def refresh(runs, state, owner_lookup, now_ms, *, grace_seconds=15, success_seconds=30):
    state = copy.deepcopy(state) if state else {'seen': {}, 'recent': [], 'stickyFailure': False}
    state.setdefault('notificationFloor', -1)
    seen = state['seen']
    notices = []
    incoming = {run_key(r): r for r in runs}
    current_keys = set(incoming)
    for key, entry in list(seen.items()):
        if entry['status'] not in TERMINAL and key not in incoming:
            incoming[key] = entry['record']
    for key, run in incoming.items():
        entry = seen.get(key)
        if entry is None:
            entry = {'record': run, 'status': 'running', 'start': False, 'result': False,
                     'deadSince': None, 'endedAt': None}
            seen[key] = entry
        entry['record'] = run
        status, finish = run['status'], run['finishedAt']
        if status == 'running':
            if entry['result']:
                continue  # A stale producer record must not resurrect an inferred result.
            owner = owner_lookup(run)
            if owner is None:
                status = 'unknown'
                entry['deadSince'] = None
            elif owner is False or owner != {'uid': run['ownerUid'], 'startedAt': run['ownerStartedAt']}:
                if entry['deadSince'] is None:
                    entry['deadSince'] = now_ms
                if now_ms - entry['deadSince'] >= grace_seconds * 1000:
                    status, finish = 'interrupted', now_ms
            else:
                entry['deadSince'] = None
        old_history = ((finish is not None and now_ms - finish > 60000)
                       or (not entry['start'] and run['startedAt'] <= state['notificationFloor']))
        if not entry['start']:
            entry['start'] = True
            if not old_history:
                notices.append(_notice(key, run, 'start', 'running', run['startedAt']))
        previous = entry['status']
        entry['status'], entry['endedAt'] = status, finish
        if status in TERMINAL:
            if not entry['result']:
                if not old_history:
                    notices.append(_notice(key, run, 'result', status, finish))
                entry['result'] = True
                if status != 'passed':
                    state['stickyFailure'] = True
            elif status != previous and status != 'passed':
                state['stickyFailure'] = True

    # Current accepted records take priority over vanished unknown owners. A
    # conservative time watermark prevents replay when evicted IDs reappear;
    # losing some alerts at capacity is safer than duplicates or a poisoned cache.
    priority = sorted(seen, key=lambda k: (k in current_keys and seen[k]['status'] not in TERMINAL,
                                          seen[k]['status'] not in TERMINAL, k in current_keys,
                                          seen[k]['record']['updatedAt']), reverse=True)
    for key in priority[512:]:
        state['notificationFloor'] = max(state['notificationFloor'], seen[key]['record']['startedAt'])
        del seen[key]
    rows = [_row(key, entry, now_ms) for key, entry in seen.items()]
    active = sorted((r for r in rows if r['status'] not in TERMINAL), key=lambda r: r['startedAt'])
    recent = sorted((r for r in rows if r['status'] in TERMINAL), key=lambda r: r['finishedAt'], reverse=True)[:20]
    state['recent'] = recent
    status = ('failed' if state['stickyFailure'] else 'running' if active else
              'passed' if any(r['status'] == 'passed' and now_ms - r['finishedAt'] < success_seconds * 1000 for r in recent) else 'idle')
    view = {'status': status, 'count': len(active), 'active': active, 'recent': recent,
            'stickyFailure': state['stickyFailure']}
    return view, state, notices


def _notice(key, run, event, status, end):
    return {'runKey': key, 'event': event, 'status': status, 'label': run['label'],
            'source': run['source'], 'project': run['project'],
            'elapsedSeconds': max(0, (end - run['startedAt']) // 1000)}


def _row(key, entry, now):
    run = entry['record']
    return {k: run[k] for k in ('label', 'source', 'project', 'startedAt', 'jobUrl')} | {
        'runKey': key, 'status': entry['status'], 'finishedAt': entry['endedAt'],
        'elapsedSeconds': max(0, ((entry['endedAt'] if entry['endedAt'] is not None else now) - run['startedAt']) // 1000)}


class StateStore:
    """Hold an owned advisory lock across reading, mutation and atomic saving."""
    def __init__(self, path):
        self.path = Path(path)
        self.directory = self.lock = None

    def __enter__(self):
        try:
            try:
                self.path.mkdir(mode=0o700)
            except FileExistsError:
                pass
            self.directory = os.open(self.path, os.O_RDONLY | os.O_DIRECTORY | NOFOLLOW)
            checked(self.directory, os.getuid(), directory=True, private=True)
            # Exclusive first creation avoids macOS concurrent O_CREAT/NOFOLLOW
            # lookups spuriously returning ENOENT; subsequent opens never create.
            try:
                self.lock = os.open('lock', os.O_RDWR | os.O_CREAT | os.O_EXCL | NOFOLLOW, 0o600, dir_fd=self.directory)
            except FileExistsError:
                self.lock = os.open('lock', os.O_RDWR | NOFOLLOW, dir_fd=self.directory)
            checked(self.lock, os.getuid(), private=True)
            fcntl.flock(self.lock, fcntl.LOCK_EX)
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def load(self):
        try:
            state = read_json(self.directory, 'state.json', os.getuid(), private=True, limit=8 * 1024 * 1024)
        except FileNotFoundError:
            return {}
        return self._validate(state)

    @staticmethod
    def _validate(state):
        if (not isinstance(state, dict) or not {'seen', 'recent', 'stickyFailure'} <= set(state)
                or not set(state) <= {'seen', 'recent', 'stickyFailure', 'notificationFloor'}
                or not isinstance(state['seen'], dict) or len(state['seen']) > 512
                or not isinstance(state['recent'], list) or len(state['recent']) > 20
                or type(state['stickyFailure']) is not bool
                or type(state.get('notificationFloor', -1)) is not int
                or state.get('notificationFloor', -1) < -1):
            raise ValueError('Invalid private state')
        return state

    def save(self, state):
        self._validate(state)  # Never persist a cache our next poll cannot load.
        # Refuse an existing unsafe cache even if this mutation did not load it.
        try:
            read_json(self.directory, 'state.json', os.getuid(), private=True, limit=8 * 1024 * 1024)
        except FileNotFoundError:
            pass
        temp = f'.state-{uuid.uuid4()}.json'
        fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | NOFOLLOW, 0o600, dir_fd=self.directory)
        try:
            with os.fdopen(fd, 'w', closefd=False) as stream:
                json.dump(state, stream, ensure_ascii=True)
                stream.flush()
                os.fsync(fd)
            os.rename(temp, 'state.json', src_dir_fd=self.directory, dst_dir_fd=self.directory)
        finally:
            os.close(fd)
            try:
                os.unlink(temp, dir_fd=self.directory)
            except FileNotFoundError:
                pass

    def __exit__(self, *args):
        for fd in (self.lock, self.directory):
            if fd is not None:
                os.close(fd)
        self.lock = self.directory = None
