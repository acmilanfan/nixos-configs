"""Isolated real-file fixtures; never use the shared production status root."""
import json
import os
from pathlib import Path
import sys
import tempfile
import uuid

SOURCE = Path(__file__).resolve().parents[2] / 'nixos/home-manager/configs/local-ci-status'
sys.path.insert(0, str(SOURCE))
ARTIFACTS = Path.home() / 'ai/artifacts/nixos-configs/local-ci-indicator/tests'
ARTIFACTS.mkdir(parents=True, exist_ok=True)
NOW = 2_000_000
UID = os.getuid()
IDENTITY = 'Fri Nov 13 03:00:00 2026'


def fixture():
    return Path(tempfile.mkdtemp(prefix='observer-', dir=ARTIFACTS))


def run(**values):
    return dict(schemaVersion=1, runId=f'manual-{uuid.uuid4()}', source='manual',
                project='stack', label='E2E smoke', startedAt=NOW, updatedAt=NOW,
                finishedAt=None, ownerUid=UID, ownerPid=os.getpid(),
                ownerStartedAt=IDENTITY, status='running', jobUrl=None, **{}) | values


def write_run(root, record):
    directory = root / f'weekenduo-ci-status-{record["ownerUid"]}'
    directory.mkdir(mode=0o755, exist_ok=True)
    path = directory / f'{record["runId"]}.json'
    path.write_text(json.dumps(record))
    path.chmod(0o644)
    return path


def alive(record):
    return {'uid': record['ownerUid'], 'startedAt': record['ownerStartedAt']}
