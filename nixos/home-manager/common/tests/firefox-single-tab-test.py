#!/usr/bin/env python3
"""Test generated userChrome in an isolated, headless Firefox—not the user profile.

Usage: python3 firefox-single-tab-test.py /absolute/path/to/generated-userChrome.css
Only the subprocess created here is terminated. No existing Firefox is controlled.
"""
import json
import os
from pathlib import Path
import shutil
import shlex
import signal
import socket
import subprocess
import sys
import tempfile
import time


class Marionette:
    def __init__(self, connection):
        self.connection = connection
        self.counter = 0
        greeting = self.receive()
        assert greeting.get("marionetteProtocol") == 3, greeting

    def receive(self):
        prefix = b""
        while True:
            char = self.connection.recv(1)
            if not char:
                raise RuntimeError("test Firefox closed its transport")
            if char == b":":
                break
            prefix += char
            if len(prefix) > 12 or not prefix.isdigit():
                raise RuntimeError("unexpected Marionette framing")
        remaining = int(prefix)
        assert remaining <= 4 * 1024 * 1024
        payload = b""
        while remaining:
            part = self.connection.recv(remaining)
            if not part:
                raise RuntimeError("incomplete Marionette response")
            payload += part
            remaining -= len(part)
        return json.loads(payload)

    def command(self, name, params):
        self.counter += 1
        packet = json.dumps([0, self.counter, name, params]).encode()
        self.connection.sendall(str(len(packet)).encode() + b":" + packet)
        kind, counter, error, result = self.receive()
        assert kind == 1 and counter == self.counter, "unexpected response"
        if error:
            raise RuntimeError(f"{name}: {error}")
        return result

    def script(self, source):
        result = self.command("WebDriver:ExecuteScript", {"script": source, "args": [], "newSandbox": False})
        return result["value"]


def require_listener_owner(port, expected_pid):
    try:
        output = subprocess.check_output(["/usr/sbin/lsof", "-nP", "-a", f"-iTCP:{port}", "-sTCP:LISTEN", "-Fp"], text=True, stderr=subprocess.DEVNULL, timeout=5)
    except (OSError, subprocess.SubprocessError):
        raise RuntimeError("cannot verify isolated Firefox listener ownership") from None
    owners = {line[1:] for line in output.splitlines() if line.startswith("p")}
    if owners != {str(expected_pid)}:
        raise RuntimeError("refusing a Marionette listener not owned by the launched Firefox")


def begin_verified_chrome_session(client, profile, expected_pid):
    session = client.command("WebDriver:NewSession", {"capabilities": {}})
    capabilities = session.get("capabilities", {})
    actual_profile = capabilities.get("moz:profile")
    actual_pid = capabilities.get("moz:processID")
    if not isinstance(actual_profile, str) or "\0" in actual_profile or Path(actual_profile).resolve() != profile.resolve():
        raise RuntimeError("refusing a Marionette session for a different or unidentified profile")
    if type(actual_pid) is not int or actual_pid != expected_pid:
        raise RuntimeError("refusing a Marionette session for a different or unidentified process")
    client.command("Marionette:SetContext", {"value": "chrome"})


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: firefox-single-tab-test.py GENERATED_USERCHROME_CSS")
    css = Path(sys.argv[1]).resolve()
    binary = Path("/Applications/Firefox.app/Contents/MacOS/firefox")
    assert binary.is_file() and css.is_file()
    artifacts = Path.home() / "ai/artifacts/org/youtube-direct-capture"
    artifacts.mkdir(parents=True, exist_ok=True)
    profile = Path(tempfile.mkdtemp(prefix="firefox-style-profile-", dir=artifacts))
    (profile / "chrome").mkdir()
    shutil.copyfile(css, profile / "chrome/userChrome.css")
    with socket.socket() as reserve:
        reserve.bind(("127.0.0.1", 0))
        port = reserve.getsockname()[1]
    preferences = {
        "marionette.port": port,
        "toolkit.legacyUserProfileCustomizations.stylesheets": True,
        "sidebar.revamp": True,
        "sidebar.verticalTabs": True,
        "browser.startup.page": 0,
        "browser.shell.checkDefaultBrowser": False,
        "startup.homepage_welcome_url": "",
        "startup.homepage_welcome_url.additional": "",
        "datareporting.policy.dataSubmissionEnabled": False,
        "toolkit.telemetry.enabled": False,
        "app.update.auto": False,
    }
    (profile / "user.js").write_text("\n".join(f"user_pref({json.dumps(key)}, {json.dumps(value)});" for key, value in preferences.items()))
    connection = None
    with (profile / "firefox-test.log").open("w") as log:
        process = subprocess.Popen([str(binary), "-foreground", "--headless", "--no-remote", "--marionette", "--profile", str(profile)], stdout=log, stderr=log, env={**os.environ, "MOZ_HEADLESS": "1", "MOZ_REMOTE_ALLOW_SYSTEM_ACCESS": "1"})
        try:
            deadline = time.monotonic() + 40
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError(f"isolated Firefox exited; see {profile / 'firefox-test.log'}")
                try:
                    connection = socket.create_connection(("127.0.0.1", port), timeout=0.2)
                    break
                except OSError:
                    time.sleep(0.1)
            if connection is None:
                raise RuntimeError(f"isolated Firefox startup timed out; see {profile}")
            connection.settimeout(15)
            require_listener_owner(port, process.pid)
            client = Marionette(connection)
            begin_verified_chrome_session(client, profile, process.pid)
            read_style = """
                const sidebar = document.getElementById('sidebar-container');
                const style = getComputedStyle(sidebar);
                const a11y = Components.classes['@mozilla.org/accessibilityService;1']
                    .getService(Components.interfaces.nsIAccessibilityService);
                return {tabs:gBrowser.tabs.length, visibility:style.visibility,
                        opacity:style.opacity, pointerEvents:style.pointerEvents,
                        tabStripAccessible:!!a11y.getAccessibleFor(document.getElementById('tabbrowser-tabs')),
                        addressAccessible:!!a11y.getAccessibleFor(document.getElementById('urlbar-input'))};
            """
            def styles():
                deadline = time.monotonic() + 3
                while True:
                    value = client.script(read_style)
                    if (value["tabStripAccessible"] and value["addressAccessible"]) or time.monotonic() >= deadline:
                        return value
                    time.sleep(0.05)
            single = styles()
            assert single["tabs"] == 1, f"fresh isolated profile has unexpected startup tabs: {single}"
            client.script("gBrowser.addTab('about:blank', {triggeringPrincipal:Services.scriptSecurityManager.getSystemPrincipal()}); return true;")
            multiple = styles()
            (profile / "computed-styles.json").write_text(json.dumps({"single": single, "multiple": multiple}, indent=2))
            assert single["tabs"] == 1 and single["visibility"] == "visible", f"single-tab sidebar removes controls from accessibility: {single}"
            assert single["tabStripAccessible"] and single["addressAccessible"], f"single-tab browser controls inaccessible: {single}"
            assert single["opacity"] == "0" and single["pointerEvents"] == "none", f"single-tab sidebar not visually hidden/noninteractive: {single}"
            assert multiple["tabs"] == 2 and multiple["visibility"] == "visible" and multiple["opacity"] == "1", f"multi-tab sidebar unexpectedly hidden: {multiple}"
            print("PASS: actual isolated Firefox single/multiple-tab userChrome behavior")
        finally:
            if connection:
                connection.close()
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            # macOS launchers may fork despite an early startup failure. Match
            # only the exact fresh profile and main executable, never Firefox
            # by name, a shared port, or the user's existing browser profile.
            for line in subprocess.check_output(["ps", "-axo", "pid=,command="], text=True).splitlines():
                fields = line.strip().split(None, 1)
                if len(fields) != 2:
                    continue
                try:
                    args = shlex.split(fields[1])
                except ValueError:
                    continue
                if args and args[0] == str(binary) and str(profile) in args:
                    try:
                        os.kill(int(fields[0]), signal.SIGTERM)
                    except ProcessLookupError:
                        pass


if __name__ == "__main__":
    main()
