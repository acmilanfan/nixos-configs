"""GUI boundary: record data is argv/URL data, never shell or Lua source."""
import re
import subprocess
import shlex

from records import RUN_ID

COLORS = {'idle': '0xff565f89', 'running': '0xffe0af68', 'unknown': '0xffe0af68',
          'passed': '0xff9ece6a', 'failed': '0xfff7768e', 'canceled': '0xfff7768e', 'interrupted': '0xfff7768e'}
SLOTS = 20


def valid_key(key):
    if not isinstance(key, str) or ':' not in key:
        return False
    uid, run_id = key.split(':', 1)
    return bool(re.fullmatch(r'[1-9][0-9]*', uid) and RUN_ID.fullmatch(run_id))


def elapsed(seconds):
    minutes, secs = divmod(max(0, seconds), 60)
    return f'{minutes}m {secs:02d}s' if minutes else f'{secs}s'


def render(view, helper='local-ci-status'):
    active, recent = view['active'], view['recent']
    if len(active) > 1:
        label = f'{len(active)} running'
    elif active:
        label = f'{active[0]["label"][:28]} · {elapsed(active[0]["elapsedSeconds"])}'
    else:
        label = ''
    commands = [['sketchybar', '--set', 'ci_status', f'drawing={"on" if active else "off"}', 'icon=󰙨',
                 f'icon.color={COLORS[view["status"]]}', f'label={label}',
                 f'label.drawing={"on" if label else "off"}']]
    if not active:
        commands[0].append('popup.drawing=off')
    rows = active + recent
    for slot in range(SLOTS):
        args = ['sketchybar', '--set', f'ci_status.row.{slot}']
        if slot >= len(rows):
            commands.append(args + ['drawing=off', 'click_script='])
            continue
        row = rows[slot]
        click = f'{shlex.quote(helper)} open {row["runKey"]}' if row['jobUrl'] and valid_key(row['runKey']) else ''
        label = f'{row["source"]} · {row["project"]} · {row["label"]} · {row["status"]} · {elapsed(row["elapsedSeconds"])}'
        commands.append(args + ['drawing=on', f'label={label}', f'icon.color={COLORS[row["status"]]}',
                                f'click_script={click}'])
    overflow = max(0, len(rows) - SLOTS)
    commands.append(['sketchybar', '--set', 'ci_status.overflow', f'drawing={"on" if overflow else "off"}',
                     f'label=+{overflow} more (local-ci-status list)'])
    commands.append(['sketchybar', '--set', 'ci_status.ack',
                     f'drawing={"on" if view["stickyFailure"] else "off"}',
                     f'click_script={shlex.quote(helper)} ack'])
    return commands


def invoke(argv, runner=subprocess.run):
    try:
        return runner(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                      stderr=subprocess.DEVNULL, timeout=3).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def apply_view(view, runner=subprocess.run, helper='local-ci-status'):
    # Batch all property assignments into one IPC call, retaining argv boundaries.
    commands = render(view, helper=helper)
    return invoke(['sketchybar'] + [arg for command in commands for arg in command[1:]], runner)


def deliver(notice, runner=subprocess.run):
    # Fixed AppleScript; title/body travel as argv, never interpolated source.
    source = 'Local CI' if notice['source'] == 'ci' else 'Local E2E'
    result = 'started' if notice['event'] == 'start' else notice['status']
    title = f'{source}: {result}'
    body = (f'{notice["project"]} · {notice["label"][:80]} · '
            f'{min(999999999, max(0, notice["elapsedSeconds"]))}s')
    return invoke(['/usr/bin/osascript', '-e', 'on run argv', '-e',
                   'display notification (item 2 of argv) with title (item 1 of argv)',
                   '-e', 'end run', '--', title, body], runner)
