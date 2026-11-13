import importlib.util
import json
import os
from pathlib import Path
import subprocess
import unittest

from support import NOW, SOURCE, UID, alive, fixture, run, write_run
from observer import StateStore, refresh
import presentation


def cli_module():
    spec = importlib.util.spec_from_file_location('status_cli', SOURCE / '__main__.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Presentation(unittest.TestCase):
    def test_no_active_runs_hide_icon_and_close_popup_without_erasing_history(self):
        for status in ('idle', 'passed', 'failed', 'canceled', 'interrupted'):
            items = [] if status == 'idle' else [run(status=status, finishedAt=NOW, updatedAt=NOW)]
            view, _, _ = refresh(items, {}, alive, NOW)
            before = json.dumps(view, sort_keys=True)
            command = presentation.render(view)[0]
            self.assertIn('drawing=off', command, status)
            self.assertIn('popup.drawing=off', command, status)
            self.assertEqual(json.dumps(view, sort_keys=True), before)

    def test_running_completed_and_new_running_transition_controls_visibility(self):
        item = run()
        view, state, _ = refresh([item], {}, alive, NOW)
        self.assertIn('drawing=on', presentation.render(view)[0])
        item |= {'status': 'failed', 'finishedAt': NOW + 1000, 'updatedAt': NOW + 1000}
        view, state, _ = refresh([item], state, alive, NOW + 1000)
        self.assertIn('drawing=off', presentation.render(view)[0])
        view, _, _ = refresh([run()], state, alive, NOW + 2000)
        self.assertIn('drawing=on', presentation.render(view)[0])
        self.assertTrue(view['stickyFailure'])

    def test_noninteractive_popup_clicks_use_the_packaged_absolute_helper(self):
        item = run(source='ci', runId='ci-123', project='backend', jobUrl='https://gitlab.com/weekenduo/backend/-/jobs/123')
        view, _, _ = refresh([item], {}, alive, NOW)
        commands = presentation.render(view, helper='/fixture/profile/bin/local-ci-status')
        self.assertTrue(any(arg == f'click_script=/fixture/profile/bin/local-ci-status open {UID}:ci-123'
                            for cmd in commands for arg in cmd))

    def test_rendered_colors_counts_elapsed_and_sticky_failure_keep_active_rows(self):
        for status, color in [('idle', '0xff565f89'), ('running', '0xffe0af68'),
                              ('passed', '0xff9ece6a'), ('failed', '0xfff7768e')]:
            item = run()
            view, _, _ = refresh([item], {}, alive, NOW + 65000)
            view['status'] = status
            commands = presentation.render(view)
            self.assertIn(f'icon.color={color}', commands[0])
            self.assertTrue(any('1m 05s' in arg for cmd in commands for arg in cmd))
        idle, _, _ = refresh([], {}, alive, NOW)
        self.assertIn('label=', presentation.render(idle)[0])
        many, _, _ = refresh([run() for _ in range(23)], {}, alive, NOW)
        commands = presentation.render(many)
        self.assertIn('label=23 running', commands[0])
        self.assertTrue(any('+3 more' in arg for cmd in commands for arg in cmd))

    def test_labels_are_only_data_and_only_validated_keys_enter_click_scripts(self):
        label = "x' ; touch /malicious $(whoami) --set evil"
        view, _, _ = refresh([run(label=label)], {}, alive, NOW)
        commands = presentation.render(view)
        self.assertTrue(any(label in arg for cmd in commands for arg in cmd if arg.startswith('label=')))
        self.assertFalse(any(label in arg for cmd in commands for arg in cmd if not arg.startswith('label=')))
        for cmd in commands:
            self.assertNotIn('evil', cmd)
        view['active'][0]['runKey'] = "1:ci-1;touch /malicious"
        self.assertFalse(any('touch' in arg for cmd in presentation.render(view) for arg in cmd if arg.startswith('click_script=')))

    def test_notifications_use_fixed_osascript_script_with_title_and_body_as_argv(self):
        calls = []
        def capture(argv, **kwargs):
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 0)
        notice = {'event': 'result', 'status': 'failed', 'label': 'full & x=$(cmd)',
                  'source': 'manual', 'project': 'stack', 'elapsedSeconds': 9}
        self.assertTrue(presentation.deliver(notice, runner=capture))
        argv = calls[0]
        self.assertEqual(argv[0], '/usr/bin/osascript')
        self.assertEqual(argv.count('-e'), 3)
        self.assertIn('display notification (item 2 of argv) with title (item 1 of argv)', argv)
        self.assertEqual(argv[-2:], ['Local E2E: failed', 'stack · full & x=$(cmd) · 9s'])
        self.assertNotIn('hammerspoon://', ' '.join(argv))
        self.assertNotIn('/usr/bin/open', argv)
        script = ' '.join(argv[:argv.index('--')])
        self.assertNotIn('full & x=$(cmd)', script)
        self.assertFalse(presentation.deliver(notice, runner=lambda *a, **k: (_ for _ in ()).throw(FileNotFoundError())))
        started = notice | {'event': 'start', 'status': 'running', 'label': 'smoke', 'source': 'ci', 'project': 'backend'}
        presentation.deliver(started, runner=capture)
        self.assertEqual(calls[-1][-2:], ['Local CI: started', 'backend · smoke · 9s'])

    def test_dispatch_persists_before_native_alerts_and_reload_does_not_repeat(self):
        root = fixture()
        marker = root / 'enabled'
        marker.touch()
        config = {'sharedRoot': str(root), 'stateDir': str(root / 'cache'), 'enabledFile': str(marker)}
        item = run(status='passed', finishedAt=NOW, updatedAt=NOW)
        write_run(root, item)
        calls = []
        def capture(argv, **kwargs):
            if argv[0] == '/usr/bin/osascript':
                with StateStore(root / 'cache') as store:
                    self.assertTrue(store.load()['seen'][f'{UID}:{item["runId"]}']['result'])
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 0)
        cli = cli_module()
        cli.dispatch(config, 'refresh', now_ms=NOW, runner=capture)
        self.assertEqual(len([c for c in calls if c[0] == '/usr/bin/osascript']), 2)
        calls.clear()
        cli_module().dispatch(config, 'popup', now_ms=NOW + 1000, runner=capture)
        self.assertFalse(any(c[0] == '/usr/bin/osascript' for c in calls))
        self.assertNotIn(['sketchybar', '--set', 'ci_status', 'popup.drawing=toggle'], calls)
        write_run(root, run())
        calls.clear()
        cli.dispatch(config, 'popup', now_ms=NOW + 1500, runner=capture)
        self.assertIn(['sketchybar', '--set', 'ci_status', 'popup.drawing=toggle'], calls)
        marker.unlink()
        calls.clear()
        cli.dispatch(config, 'refresh', now_ms=NOW + 2000, runner=capture)
        self.assertEqual(calls, [])

    def test_open_uses_only_cached_revalidated_ci_url_and_refuses_manual_or_arbitrary_key(self):
        root = fixture()
        marker = root / 'enabled'
        marker.touch()
        item = run(source='ci', runId='ci-123', project='backend', jobUrl='https://gitlab.com/weekenduo/backend/-/jobs/123')
        _, state, _ = refresh([item], {}, alive, NOW)
        with StateStore(root / 'cache') as store:
            store.save(state)
        calls = []
        def capture(argv, **kwargs):
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 0)
        cli = cli_module()
        config = {'enabledFile': str(marker), 'stateDir': str(root / 'cache')}
        cli.dispatch(config, 'open', key=f'{UID}:ci-123', now_ms=NOW, runner=capture)
        self.assertEqual(calls, [['/usr/bin/open', 'https://gitlab.com/weekenduo/backend/-/jobs/123']])
        calls.clear()
        cli.dispatch(config, 'open', key='file:///etc/passwd', now_ms=NOW, runner=capture)
        self.assertEqual(calls, [])
        state['seen'][f'{UID}:ci-123']['record']['jobUrl'] = 'https://evil.test'
        with StateStore(root / 'cache') as store:
            store.save(state)
        cli.dispatch(config, 'open', key=f'{UID}:ci-123', now_ms=NOW, runner=capture)
        self.assertEqual(calls, [])

    def test_shared_bar_and_plugin_are_inert_without_feature_marker(self):
        root = fixture()
        (root / '.config/sketchybar').mkdir(parents=True)
        dotfiles = SOURCE.parents[3] / 'dotfiles/sketchybar'
        assets = root / 'assets'
        (assets / 'plugins').mkdir(parents=True)
        (assets / 'colors.sh').write_text('')
        (assets / 'defaults.sh').write_text('')
        daemon = assets / 'plugins/system_info_daemon.sh'
        daemon.write_text('#!/bin/sh\nexit 0\n')
        daemon.chmod(0o700)
        calls_file = root / 'calls'
        config = dotfiles / 'sketchybarrc'
        # The full config also pkills/spawns a system-info daemon. Both process
        # boundaries MUST be inert, not just the sketchybar command itself.
        source = 'pkill() { :; }; sketchybar() { printf "%s\\n" "$*" >> "$CALLS"; }; export -f sketchybar pkill; source "$CONFIG"'
        result = subprocess.run(['/bin/bash', '-c', source], env=dict(os.environ, HOME=str(root),
                                CONFIG=str(config), CONFIG_DIR=str(assets), CALLS=str(calls_file), PATH='/usr/bin:/bin'),
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('ci_status', calls_file.read_text())
        result = subprocess.run([str(dotfiles / 'plugins/ci_status.sh')],
                                env={'HOME': str(root), 'PATH': '/usr/bin:/bin'}, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)


class BarInitialization(unittest.TestCase):
    def setUp(self):
        root = fixture()
        marker = root / '.config/local-ci-status/enabled'
        marker.parent.mkdir(parents=True)
        marker.touch()
        assets = root / 'assets'
        (assets / 'plugins').mkdir(parents=True)
        for name in ('colors.sh', 'defaults.sh'):
            (assets / name).write_text('')
        daemon = assets / 'plugins/system_info_daemon.sh'
        daemon.write_text('#!/bin/sh\nexit 0\n')
        daemon.chmod(0o700)
        (root / 'bin').mkdir()
        helper = root / 'bin/local-ci-status'
        self.helper_calls = root / 'helper-calls'
        helper.write_text(f'#!/bin/sh\nprintf "%s\\n" "$*" >> "{self.helper_calls}"\nprintf "3\\n"\n')
        helper.chmod(0o700)
        calls = root / 'calls'
        config = SOURCE.parents[3] / 'dotfiles/sketchybar/sketchybarrc'
        source = '''pkill() { :; }
sketchybar() { printf '%s\\0' "$@" >> "$CALLS"; printf '\\0' >> "$CALLS"; }
export -f sketchybar pkill
source "$CONFIG"
'''
        result = subprocess.run(['/bin/bash', '-c', source], capture_output=True, text=True, timeout=10,
                                env={'HOME': str(root), 'CONFIG': str(config), 'CONFIG_DIR': str(assets),
                                     'CALLS': str(calls), 'PATH': f'{root}/bin:/usr/bin:/bin'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.commands = [[v.decode() for v in c.split(b'\0')] for c in calls.read_bytes().split(b'\0\0') if c]

    def test_ci_starts_hidden_but_keeps_polling_while_hidden(self):
        command = next(c for c in self.commands if c[:4] == ['--add', 'item', 'ci_status', 'right'])
        self.assertIn('drawing=off', command)
        self.assertIn('updates=on', command)
        self.assertIn('update_freq=0', command)
        self.assertFalse(self.helper_calls.exists(), 'bar initialization should not query a periodic interval')

    def test_ci_is_immediately_left_of_help_in_the_right_aligned_group(self):
        names = []
        for cmd in self.commands:
            for index in range(len(cmd) - 3):
                if cmd[index:index+2] == ['--add', 'item'] and cmd[index+3] == 'right':
                    names.append(cmd[index+2])
        # Right-aligned items render from right to left in registration order.
        self.assertEqual(list(reversed(names))[:2], ['ci_status', 'help_menu'])
