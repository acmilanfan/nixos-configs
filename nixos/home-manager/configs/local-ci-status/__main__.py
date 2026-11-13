"""Noninteractive desktop observer entry point; all mutations hold one lock."""
import argparse
import json
from pathlib import Path
import sys
import time
import subprocess

from observer import StateStore, acknowledge, refresh
from records import owner_lookup, producer_uids, read_runs, validate
from presentation import apply_view, deliver, invoke, valid_key


def cycle(config, command, now_ms):
    state_dir = config.get('stateDir', str(Path.home() / '.cache/local-ci-status'))
    with StateStore(state_dir) as store:
        state = store.load()
        runs = read_runs(config, producer_uids(config.get('ciUser', 'weekenduo-ci')), now_ms)
        # Include missing source records when checking identities after wake/reload.
        prior = [e['record'] for e in state.get('seen', {}).values() if not e['result']]
        view, state, notices = refresh(runs, state, owner_lookup(runs + prior), now_ms,
                                       grace_seconds=config.get('finalizationGraceSeconds', 15),
                                       success_seconds=config.get('successSeconds', 30))
        if command == 'ack':
            state = acknowledge(state)
            view, state, _ = refresh(runs, state, owner_lookup(runs + prior), now_ms,
                                     grace_seconds=config.get('finalizationGraceSeconds', 15),
                                     success_seconds=config.get('successSeconds', 30))
        store.save(state)  # Claims must reach disk before any GUI notification dispatch.
    return view, notices


def dispatch(config, command, *, key=None, now_ms=None, runner=subprocess.run):
    marker = config.get('enabledFile', str(Path.home() / '.config/local-ci-status/enabled'))
    if not Path(marker).is_file():
        return {}
    now_ms = time.time_ns() // 1000000 if now_ms is None else now_ms
    if command == 'open':
        if not valid_key(key):
            return {}
        with StateStore(config.get('stateDir', str(Path.home() / '.cache/local-ci-status'))) as store:
            entry = store.load().get('seen', {}).get(key)
            if entry:
                try:
                    record = validate(entry['record'], int(key.split(':')[0]), now_ms)
                    if record['jobUrl']:
                        invoke(['/usr/bin/open', record['jobUrl']], runner)
                except (ValueError, TypeError, KeyError):
                    pass
        return {}
    view, notices = cycle(config, command, now_ms)
    for notice in notices:
        deliver(notice, runner)
    if command != 'list':
        apply_view(view, runner, helper=config.get('helperCommand', 'local-ci-status'))
    if command == 'popup' and view['active']:
        invoke(['sketchybar', '--set', 'ci_status', 'popup.drawing=toggle'], runner)
    return view


def main(argv=None):
    parser = argparse.ArgumentParser(description='Observed local CI and E2E activity')
    parser.add_argument('--config', default=str(Path.home() / '.config/local-ci-status/config.json'))
    parser.add_argument('command', choices=['refresh', 'observe', 'list', 'ack', 'popup', 'open', 'interval'])
    parser.add_argument('key', nargs='?')
    args = parser.parse_args(argv)
    try:
        config = json.loads(Path(args.config).read_text())
        if args.command == 'interval':
            interval = config.get('interval', 3)
            if type(interval) is not int or not 1 <= interval <= 60:
                raise ValueError('Invalid interval')
            print(interval)
            return 0
        view = dispatch(config, args.command, key=args.key)
        if args.command == 'list':
            print(json.dumps(view))
        elif args.command == 'observe':
            print(json.dumps({'activeCount': view.get('count', 0)}))
        return 0
    except (OSError, ValueError, TypeError, KeyError):
        print('local-ci-status: observer unavailable (advisory)', file=sys.stderr)
        return 0


if __name__ == '__main__':
    raise SystemExit(main())
