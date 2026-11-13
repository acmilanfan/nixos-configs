import json
import os
import unittest
from unittest.mock import patch

from support import NOW, UID, fixture, run, write_run
import records


class Records(unittest.TestCase):
    def test_configured_project_allowlist_can_restrict_ci_producers(self):
        root = fixture()
        write_run(root, run(source='ci', runId='ci-123', project='frontend', jobUrl='https://gitlab.com/weekenduo/duomobile/-/jobs/123'))
        self.assertEqual(records.read_runs({'sharedRoot': str(root), 'allowedProjects': ['weekenduo/backend']}, {UID}, NOW), [])

    def test_only_authorized_uids_are_read_and_missing_ci_account_is_harmless(self):
        root = fixture()
        good = run()
        write_run(root, good)
        write_run(root, run(ownerUid=UID + 200))
        with patch('pwd.getpwnam', side_effect=KeyError):
            identities = records.producer_uids('weekenduo-ci')
        self.assertEqual(identities, {UID})
        self.assertEqual(records.read_runs({'sharedRoot': str(root)}, identities, NOW), [good])

    def test_bad_files_and_directories_are_ignored_without_following_links(self):
        for kind in ('malformed', 'oversized', 'link', 'writable', 'wrong-owner', 'hardlink', 'dir-link', 'dir-writable'):
            with self.subTest(kind=kind):
                root = fixture()
                path = write_run(root, run())
                if kind == 'malformed':
                    path.write_text('{')
                elif kind == 'oversized':
                    path.write_bytes(b' ' * 8193)
                elif kind == 'link':
                    target = root / 'target'
                    path.rename(target)
                    path.symlink_to(target)
                elif kind == 'hardlink':
                    os.link(path, root / 'alias')
                elif kind == 'writable':
                    path.chmod(0o666)
                elif kind == 'dir-writable':
                    path.parent.chmod(0o777)
                elif kind == 'dir-link':
                    target = root / 'elsewhere'
                    path.parent.rename(target)
                    path.parent.symlink_to(target)
                else:
                    # Real file ownership cannot be changed without privilege: use another
                    # authorized directory name to exercise opened UID validation.
                    path.parent.rename(root / f'weekenduo-ci-status-{UID + 1}')
                self.assertEqual(records.read_runs({'sharedRoot': str(root)}, {UID, UID + 1}, NOW), [])

    def test_schema_label_url_and_time_are_independently_validated(self):
        for bad in ({'schemaVersion': True}, {'ownerUid': True}, {'ownerPid': 0}, {'label': 'x\n'},
                    {'label': 'x' * 81}, {'command': 'secret'}, {'updatedAt': NOW - 1},
                    {'startedAt': NOW + 60001, 'updatedAt': NOW + 60001},
                    {'status': 'passed'}, {'jobUrl': 'https://evil.test'}, {'ownerStartedAt': 'cmd;sh'}):
            with self.subTest(bad=bad):
                root = fixture()
                write_run(root, run(**bad))
                self.assertEqual(records.read_runs({'sharedRoot': str(root)}, {UID}, NOW), [])
        root = fixture()
        good = run(runId='ci-123', source='ci', project='backend', jobUrl='https://gitlab.com/weekenduo/backend/-/jobs/123')
        path = write_run(root, good)
        self.assertEqual(records.read_runs({'sharedRoot': str(root)}, {UID}, NOW), [good])
        for url in ('https://gitlab.com/weekenduo/backend/-/jobs/124', good['jobUrl'] + '?token=x',
                    'https://u:p@gitlab.com/weekenduo/backend/-/jobs/123', 'javascript:alert(1)'):
            path.write_text(json.dumps(good | {'jobUrl': url}))
            self.assertEqual(records.read_runs({'sharedRoot': str(root)}, {UID}, NOW), [])

    def test_filename_must_agree_with_payload(self):
        root = fixture()
        path = write_run(root, run())
        path.write_text(json.dumps(run()))
        self.assertEqual(records.read_runs({'sharedRoot': str(root)}, {UID}, NOW), [])

    def test_process_identity_batches_without_process_arguments(self):
        item = run(ownerPid=123)
        def ps(argv, **kwargs):
            self.assertEqual(argv, ['/bin/ps', '-p', '123', '-o', 'pid=,uid=,lstart='])
            self.assertNotIn('args', ' '.join(argv))
            return type('Result', (), {'returncode': 0, 'stdout': f'123 {UID} Fri Nov 13 03:00:00 2026\n', 'stderr': ''})()
        lookup = records.owner_lookup([item], runner=ps)
        self.assertEqual(lookup(item), {'uid': UID, 'startedAt': 'Fri Nov 13 03:00:00 2026'})
        for code, err, want in ((1, '', False), (1, 'permission denied', None)):
            result = type('Result', (), {'returncode': code, 'stdout': '', 'stderr': err})()
            self.assertEqual(records.owner_lookup([item], runner=lambda *a, **k: result)(item), want)
