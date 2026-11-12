#!/usr/bin/env python3
"""Safety regressions for the isolated Firefox test's remote-control boundary."""
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location("firefox_style_test", Path(__file__).with_name("firefox-single-tab-test.py"))
target = importlib.util.module_from_spec(spec)
spec.loader.exec_module(target)


class Endpoint:
    def __init__(self, capabilities):
        self.capabilities = capabilities
        self.calls = []

    def command(self, name, params):
        self.calls.append(name)
        if name == "WebDriver:NewSession":
            return {"sessionId": "fixture", "capabilities": self.capabilities}
        return {}


class IdentityTests(unittest.TestCase):
    profile = Path("/isolated-fixture/expected-profile")
    pid = 424242

    def test_unrelated_profile_rejected_before_chrome(self):
        endpoint = Endpoint({"moz:profile": "/unrelated/browser-profile", "moz:processID": self.pid})
        with self.assertRaises(RuntimeError):
            target.begin_verified_chrome_session(endpoint, self.profile, self.pid)
        self.assertEqual(endpoint.calls, ["WebDriver:NewSession"])

    def test_unrelated_process_rejected_before_chrome(self):
        endpoint = Endpoint({"moz:profile": str(self.profile), "moz:processID": self.pid + 1})
        with self.assertRaises(RuntimeError):
            target.begin_verified_chrome_session(endpoint, self.profile, self.pid)
        self.assertEqual(endpoint.calls, ["WebDriver:NewSession"])

    def test_missing_identity_rejected_before_chrome(self):
        endpoint = Endpoint({})
        with self.assertRaises(RuntimeError):
            target.begin_verified_chrome_session(endpoint, self.profile, self.pid)
        self.assertEqual(endpoint.calls, ["WebDriver:NewSession"])

    def test_matching_identity_may_enter_chrome(self):
        endpoint = Endpoint({"moz:profile": str(self.profile), "moz:processID": self.pid})
        target.begin_verified_chrome_session(endpoint, self.profile, self.pid)
        self.assertEqual(endpoint.calls, ["WebDriver:NewSession", "Marionette:SetContext"])

    def test_foreign_listener_rejected(self):
        with patch.object(target.subprocess, "check_output", return_value="p777777\n"):
            with self.assertRaises(RuntimeError):
                target.require_listener_owner(12345, self.pid)

    def test_matching_listener_accepted(self):
        with patch.object(target.subprocess, "check_output", return_value=f"p{self.pid}\n"):
            target.require_listener_owner(12345, self.pid)


if __name__ == "__main__":
    unittest.main()
