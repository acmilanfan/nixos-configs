#!/usr/bin/env python3
"""Exercise actual Newsboat UI + SQLite in a fresh HOME and owned tmux server.

NEWSBOAT_TEST_BINARY selects the built package. No real cache, account, collection,
or network is used: feeds are local files and the bookmark command is a stub.
"""
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import sqlite3
import subprocess
import tempfile
import time
import uuid


def wait_for(predicate, description, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError(f"timed out: {description}")


def main():
    binary = os.environ.get("NEWSBOAT_TEST_BINARY") or shutil.which("newsboat")
    tmux = shutil.which("tmux")
    assert binary and tmux, "Newsboat and tmux are required"
    artifacts = Path.home() / "ai/artifacts/org/youtube-direct-capture"
    artifacts.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix="newsboat-read-fixture-", dir=artifacts))
    cases = [
        ("list-saved", "saved", False, True, False, False, 0),
        ("list-existing", "existing", False, True, False, False, 0),
        ("list-failed", "failed", False, True, False, False, 1),
        ("list-missing-helper", "missing", False, True, False, False, 1),
        ("list-already-read", "saved", False, True, True, False, 0),
        ("article-saved", "saved", True, True, False, False, 0),
        ("article-failed", "failed", True, True, False, False, 1),
        ("article-failed-already-read", "failed", True, True, True, False, 0),
        ("disabled-list", "saved", False, False, False, False, 1),
        ("interactive-list", "saved", False, True, False, True, 1),
        ("query-saved", "saved", False, True, False, False, 0),
        ("query-failed", "failed", False, True, False, False, 1),
        ("hidden-list-saved", "saved", False, True, False, False, 0),
    ]
    for name, outcome, article_view, enabled, initially_read, interactive, expected in cases:
        home = root / name
        home.mkdir()
        env = {**os.environ, "HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"),
               "XDG_DATA_HOME": str(home / ".local/share"), "TERM": "xterm-256color"}
        feed = home / "feed.xml"
        feed.write_text('''<?xml version="1.0"?><rss version="2.0"><channel>
<title>Fixture feed</title><link>https://example.invalid/</link><description>local</description>
<item><title>First video</title><link>https://www.youtube.com/watch?v=3V_wgHB4eFw</link>
<guid isPermaLink="false">fixture-first</guid><pubDate>Wed, 11 Nov 2026 10:00:00 GMT</pubDate><description>fixture</description></item>
<item><title>Unrelated video</title><link>https://www.youtube.com/watch?v=abcdefghijk</link>
<guid isPermaLink="false">fixture-other</guid><pubDate>Wed, 11 Nov 2026 11:00:00 GMT</pubDate><description>fixture</description></item>
</channel></rss>''')
        urls, config, cache = home / "urls", home / "config", home / "cache.db"
        query = '\"query:Fixture query:unread = \\\"yes\\\"\"\n' if name.startswith("query-") else ""
        urls.write_text(query + feed.as_uri() + "\n")
        marker = home / "bookmark-called"
        helper = home / "bookmark-stub"
        helper.write_text("#!/bin/sh\n" + f"printf '%s\\n' \"$1\" >> {shlex.quote(str(marker))}\n" +
                          ("printf '%s\\n' 'fixture save failed'\nexit 7\n" if outcome in ("failed", "missing") else "exit 0\n"))
        helper.chmod(0o700)
        base = f'''auto-reload no
cleanup-on-quit no
confirm-exit no
show-read-feeds yes
show-read-articles {"no" if name.startswith("hidden-") else "yes"}
mark-as-read-on-hover no
goto-first-unread no
article-sort-order date-asc
bookmark-autopilot yes
bookmark-interactive {"yes" if interactive else "no"}
bookmark-cmd {json.dumps(str(helper))}
bind-key s bookmark articlelist
bind-key s bookmark article
'''
        # Initialize solely from this local file, before enabling the new option.
        config.write_text(base)
        args = [str(binary), "-u", str(urls), "-C", str(config), "-c", str(cache)]
        seeded = subprocess.run([*args, "-x", "reload"], env=env, text=True, capture_output=True, timeout=20)
        assert seeded.returncode == 0, f"{name}: fixture seed failed: {seeded.stderr}"
        with sqlite3.connect(cache) as db:
            rows = dict(db.execute("SELECT guid, unread FROM rss_item"))
            assert rows == {"fixture-first": 1, "fixture-other": 1}, rows
            if initially_read:
                db.execute("UPDATE rss_item SET unread=0 WHERE guid='fixture-first'")
        config.write_text(base + f'bookmark-mark-read {"yes" if enabled else "no"}\n')
        socket = "newsboat-read-" + uuid.uuid4().hex
        def tm(*arguments, check=True):
            return subprocess.run([tmux, "-L", socket, *arguments], env=env, text=True, capture_output=True, timeout=10, check=check)
        def screen():
            result = tm("capture-pane", "-p", "-t", "fixture:0.0", check=False)
            return result.stdout
        def keys(*values):
            tm("send-keys", "-t", "fixture:0.0", *values)
        try:
            # remain-on-exit preserves startup errors for a meaningful RED.
            # Newsboat needs a tty for stdout; retain stderr only.
            command = shlex.join(args) + " 2>" + shlex.quote(str(home / "stderr"))
            tm("-f", "/dev/null", "new-session", "-d", "-s", "fixture", "-x", "120", "-y", "35", "/bin/sh")
            tm("set-option", "-t", "fixture", "remain-on-exit", "on")
            keys(command, "Enter")
            def ready():
                error = (home / "stderr").read_text() if (home / "stderr").exists() else ""
                assert "unknown command" not in error.lower(), f"{name}: {error}"
                return "Fixture feed" in screen()
            wait_for(ready, f"{name}: feed list")
            keys("Enter")
            wait_for(lambda: "First video" in screen(), f"{name}: article list")
            # Do not assume a particular sort direction or restored selection.
            target = re.search(r"^\s*(\d+).*First video\s*$", screen(), re.M)
            assert target, f"{name}: target row not visible"
            keys(":", target.group(1), "Enter")
            if article_view:
                keys("Enter")
                wait_for(lambda: "Feed:" in screen(), f"{name}: article view")
            # Inspect state while Newsboat is running; quitting article view
            # normally marks read independently and would mask a failed save.
            keys("s")
            wait_for(marker.exists, f"{name}: bookmark invocation")
            wait_for(lambda: "Saved bookmark." in screen() or "Error while saving bookmark:" in screen(), f"{name}: bookmark completion")
            assert marker.read_text().strip() == "https://www.youtube.com/watch?v=3V_wgHB4eFw", "wrong article selected by fixture"
            with sqlite3.connect(cache) as db:
                actual = dict(db.execute("SELECT guid, unread FROM rss_item"))
            assert actual["fixture-first"] == expected, f"{name}: expected unread={expected}, got {actual}"
            assert actual["fixture-other"] == 1, f"{name}: unrelated article was altered"
            (home / "screen.txt").write_text(screen())
            print(f"PASS: {name}")
        except Exception:
            (home / "screen.txt").write_text(screen())
            raise
        finally:
            # This random socket belongs only to this fixture, never the user's server.
            tm("kill-server", check=False)
    print(f"PASS: {len(cases)} isolated Newsboat read-marking cases; artifacts: {root}")


if __name__ == "__main__":
    main()
