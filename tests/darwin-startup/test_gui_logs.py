"""Run with: python3 -m unittest discover -s tests/darwin-startup -v."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "darwin/scripts/prepare-gui-logs.sh"
ARTIFACTS = Path.home() / "ai/artifacts/nixos-configs/darwin-startup-tests"
NAMES = (
    "darwin-startup.log", "darwin-startup.err.log",
    "vicinae-em-keepalive.log", "vicinae-em-keepalive.err.log",
)


@unittest.skipIf(os.geteuid() == 0, "Run as the GUI user, not root")
class GuiLogs(unittest.TestCase):
    def setUp(self):
        ARTIFACTS.mkdir(parents=True, exist_ok=True)
        self.workspace = Path(tempfile.mkdtemp(dir=ARTIFACTS))
        self.logs = self.workspace / "Logs"

    def run_helper(self):
        return subprocess.run(
            ["/bin/bash", str(SCRIPT), str(self.logs)],
            capture_output=True, text=True, timeout=10,
        )

    def test_missing_logs_are_created_private_and_user_owned(self):
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in NAMES:
            path = self.logs / name
            self.assertTrue(path.is_file(), name)
            self.assertEqual(path.stat().st_uid, os.getuid())
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            with path.open("a") as stream:
                stream.write("launchd can append\n")

    def test_existing_writable_logs_keep_content_and_inode(self):
        self.logs.mkdir()
        path = self.logs / NAMES[0]
        path.write_text("preserve existing history\n")
        inode = path.stat().st_ino
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(path.read_text(), "preserve existing history\n")
        self.assertEqual(path.stat().st_ino, inode)
        self.assertEqual(list(self.logs.glob(".darwin-startup-logs.*")), [])

    def test_unwritable_logs_are_preserved_and_replaced(self):
        self.logs.mkdir()
        path = self.logs / NAMES[0]
        path.write_text("old protected history\n")
        path.chmod(0o400)
        self.assertFalse(os.access(path, os.W_OK))
        inode = path.stat().st_ino
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotEqual(path.stat().st_ino, inode)
        self.assertTrue(os.access(path, os.W_OK))
        backups = list(self.logs.glob(f".darwin-startup-logs.*/{NAMES[0]}"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "old protected history\n")
        self.assertEqual(backups[0].stat().st_ino, inode)

    def test_symlink_is_rejected_without_touching_target(self):
        self.logs.mkdir()
        target = self.workspace / "target"
        target.write_text("leave alone\n")
        (self.logs / NAMES[0]).symlink_to(target)
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing", result.stderr)
        self.assertEqual(target.read_text(), "leave alone\n")
        self.assertTrue((self.logs / NAMES[0]).is_symlink())

    def test_directory_at_log_path_is_rejected(self):
        (self.logs / NAMES[0]).mkdir(parents=True)
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing", result.stderr)
        self.assertTrue((self.logs / NAMES[0]).is_dir())

    def test_unwritable_hardlink_target_is_not_modified(self):
        self.logs.mkdir()
        target = self.workspace / "target"
        target.write_text("protected target\n")
        target.chmod(0o400)
        os.link(target, self.logs / NAMES[0])
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(target.read_text(), "protected target\n")
        self.assertEqual(target.stat().st_mode & 0o777, 0o400)
        self.assertNotEqual(target.stat().st_ino, (self.logs / NAMES[0]).stat().st_ino)


if __name__ == "__main__":
    unittest.main()
