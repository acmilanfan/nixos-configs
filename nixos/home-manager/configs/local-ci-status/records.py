"""Read only explicitly authorized producer records, without following links."""
import itertools
import json
import os
import pwd
import re
import stat
import subprocess
import unicodedata

RUN_ID = re.compile(r'(?:ci-[1-9][0-9]*|manual-[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12})\Z')
TERMINAL = {'passed', 'failed', 'canceled', 'interrupted'}
FIELDS = {'schemaVersion', 'runId', 'source', 'project', 'label', 'startedAt', 'updatedAt',
          'finishedAt', 'ownerUid', 'ownerPid', 'ownerStartedAt', 'status', 'jobUrl'}
NOFOLLOW = os.O_NOFOLLOW | os.O_NONBLOCK


def producer_uids(ci_user='weekenduo-ci'):
    uids = {os.getuid()}
    try:
        uids.add(pwd.getpwnam(ci_user).pw_uid)
    except KeyError:
        pass
    return uids


def integer(value, minimum=0):
    return type(value) is int and minimum <= value <= 9007199254740991


def validate(run, uid, now_ms):
    if not isinstance(run, dict) or set(run) != FIELDS:
        raise ValueError('Invalid record fields')
    if type(run['schemaVersion']) is not int or run['schemaVersion'] != 1:
        raise ValueError('Invalid record version')
    if (not isinstance(run['runId'], str) or not RUN_ID.fullmatch(run['runId'])
            or run['source'] not in ('ci', 'manual') or run['project'] not in ('backend', 'frontend', 'stack')
            or not integer(run['ownerUid'], 1) or run['ownerUid'] != uid or not integer(run['ownerPid'], 1)):
        raise ValueError('Invalid record identity')
    label = run['label']
    identity = run['ownerStartedAt']
    if (not isinstance(label, str) or len(label) > 80 or any(unicodedata.category(c).startswith('C') for c in label)
            or not isinstance(identity, str) or not re.fullmatch(r'[A-Za-z0-9 :+\-]{1,64}', identity)):
        raise ValueError('Invalid display or owner identity')
    start, update, finish = (run[k] for k in ('startedAt', 'updatedAt', 'finishedAt'))
    if not integer(start) or not integer(update) or not start <= update <= now_ms + 60000:
        raise ValueError('Invalid record time')
    status = run['status']
    if status == 'running':
        if finish is not None:
            raise ValueError('Running record has finish')
    elif not isinstance(status, str) or status not in TERMINAL or not integer(finish) or not start <= finish <= update:
        raise ValueError('Invalid terminal record')
    if run['source'] == 'manual':
        if not run['runId'].startswith('manual-') or run['jobUrl'] is not None:
            raise ValueError('Invalid manual record')
    else:
        repo = {'backend': 'backend', 'frontend': 'duomobile'}.get(run['project'])
        expected = f'https://gitlab.com/weekenduo/{repo}/-/jobs/{run["runId"][3:]}'
        if not repo or not run['runId'].startswith('ci-') or run['jobUrl'] != expected:
            raise ValueError('Invalid job URL')
    return run


def checked(fd, uid, directory=False, private=False):
    info = os.fstat(fd)
    correct_type = stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)
    forbidden = 0o077 if private else 0o022
    if not correct_type or info.st_uid != uid or info.st_mode & forbidden or (not directory and info.st_nlink != 1):
        raise ValueError('Unsafe owned path')
    return info


def unique_fields(pairs):
    obj = {}
    for key, value in pairs:
        if key in obj:
            raise ValueError('Duplicate JSON field')
        obj[key] = value
    return obj


def read_json(dir_fd, name, uid, *, private=False, limit=8192):
    fd = os.open(name, os.O_RDONLY | NOFOLLOW, dir_fd=dir_fd)
    try:
        info = checked(fd, uid, private=private)
        if info.st_size > limit:
            raise ValueError('Oversized JSON')
        with os.fdopen(fd, 'rb', closefd=False) as stream:
            content = stream.read(limit + 1)
        if len(content) > limit:
            raise ValueError('Oversized JSON')
        return json.loads(content, object_pairs_hook=unique_fields)
    finally:
        os.close(fd)


def read_runs(config, identities, now_ms):
    runs = []
    try:
        root = os.open(config.get('sharedRoot', '/Users/Shared'), os.O_RDONLY | os.O_DIRECTORY | NOFOLLOW)
    except OSError:
        return runs
    try:
        for uid in sorted(identities):
            directory = None
            try:
                directory = os.open(f'weekenduo-ci-status-{uid}', os.O_RDONLY | os.O_DIRECTORY | NOFOLLOW, dir_fd=root)
                checked(directory, uid, directory=True)
                with os.scandir(directory) as entries:
                    names = [e.name for e in itertools.islice(entries, 1024) if e.name.endswith('.json')]
                for name in sorted(names)[:256]:
                    if not RUN_ID.fullmatch(name[:-5]):
                        continue
                    try:
                        run = validate(read_json(directory, name, uid), uid, now_ms)
                        project = {'backend': 'weekenduo/backend', 'frontend': 'weekenduo/duomobile'}.get(run['project'])
                        if run['source'] == 'ci' and project not in config.get('allowedProjects', ['weekenduo/backend', 'weekenduo/duomobile']):
                            continue
                        if run['runId'] == name[:-5]:
                            runs.append(run)
                    except (OSError, ValueError, TypeError, UnicodeError):
                        continue
            except (OSError, ValueError):
                continue
            finally:
                if directory is not None:
                    os.close(directory)
    finally:
        os.close(root)
    return runs


def owner_lookup(runs, runner=subprocess.run):
    pids = sorted({r['ownerPid'] for r in runs})
    if not pids:
        return lambda run: None
    try:
        result = runner(['/bin/ps', '-p', ','.join(map(str, pids)), '-o', 'pid=,uid=,lstart='],
                        capture_output=True, text=True, timeout=3,
                        env={'LC_ALL': 'C', 'TZ': 'UTC', 'PATH': '/usr/bin:/bin'})
        if result.returncode not in (0, 1) or result.stderr.strip():
            return lambda run: None
        found = {}
        for line in result.stdout.splitlines():
            match = re.fullmatch(r'\s*(\d+)\s+(\d+)\s+(.+?)\s*', line)
            if not match:
                return lambda run: None
            found[int(match[1])] = {'uid': int(match[2]), 'startedAt': ' '.join(match[3].split())}
        return lambda run: found.get(run['ownerPid'], False)
    except (OSError, subprocess.SubprocessError):
        return lambda run: None
