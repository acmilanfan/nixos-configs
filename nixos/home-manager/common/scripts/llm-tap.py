"""Logging proxy that measures prefix-cache health in real opencode sessions.

bench-llm measures what the engine CAN do. This measures what opencode
ACTUALLY does, which is the difference between a fast session and a slow one.

Point opencode at this proxy instead of the engine:

    llm-tap --listen 8090 --upstream http://127.0.0.1:8083

Per request it logs prompt size and, crucially, the longest common prefix
(LCP) against the previous request in the session.

Why LCP is the number that matters
----------------------------------
In agentic coding the conversation grows by appending, so consecutive turns
should share ~95%+ of their prefix. When they do, the engine reuses the cached
KV and each turn after the first prefills only the new tokens - nearly free.

If LCP collapses toward zero, something dynamic sits at the HEAD of the prompt
(a timestamp, cwd, git status, an injected reminder), silently invalidating the
whole cache. Every turn then pays a full cold prefill. On a dense 27B at
~93 prompt tok/s, a 60k-token context means roughly ten minutes per turn - far
larger than any other effect measured so far.

This is a diagnostic, not a fix. A low LCP tells you to go look at what sits at
the front of the prompt.
"""

import argparse
import json
import os
import re
import sys
import threading
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "content-length",
}

_USAGE_RE = re.compile(r'"prompt_tokens"\s*:\s*(\d+)')

_state_lock = threading.Lock()
_prev_prompt = {"text": None}
_seq = {"n": 0}


def flatten_messages(body):
    """Serialize chat messages into the flat string the engine effectively sees.

    Approximate by design: we only need a stable representation to diff
    consecutive requests, not the engine's exact template.
    """
    parts = []
    for m in body.get("messages") or []:
        role = m.get("role", "")
        content = m.get("content")
        if isinstance(content, list):
            # Multimodal / content-part form.
            chunks = []
            for c in content:
                if isinstance(c, dict):
                    chunks.append(c.get("text") or c.get("type") or "")
                else:
                    chunks.append(str(c))
            content = " ".join(chunks)
        parts.append("<%s>%s" % (role, content if content is not None else ""))
    # Tool definitions are part of the prefix too, and a common source of
    # instability if their order is not deterministic.
    if body.get("tools"):
        parts.append("<tools>" + json.dumps(body["tools"], sort_keys=True))
    return "\n".join(parts)


def longest_common_prefix(a, b):
    if not a or not b:
        return 0
    n = min(len(a), len(b))
    lo, hi = 0, n
    # Binary search on prefix length; slicing comparison is C-speed, so this
    # stays fast even for multi-hundred-KB prompts.
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if a[:mid] == b[:mid]:
            lo = mid
        else:
            hi = mid - 1
    return lo


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    # Silence the default per-request stderr spam; we emit our own summary.
    def log_message(self, fmt, *a):
        pass

    def _proxy(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""

        record = None
        if raw and self.path.endswith("/chat/completions"):
            record = self._analyze(raw)

        url = self.server.upstream.rstrip("/") + self.path
        headers = {
            k: v for k, v in self.headers.items()
            if k.lower() not in HOP_BY_HOP
        }
        req = urllib.request.Request(
            url, data=raw or None, headers=headers, method=self.command
        )

        try:
            resp = urllib.request.urlopen(req, timeout=self.server.timeout_s)
        except urllib.error.HTTPError as e:
            resp = e
        except Exception as e:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(("upstream error: %s" % e).encode())
            if record:
                record["error"] = str(e)[:200]
                self.server.emit(record)
            return

        self.send_response(resp.status)
        for k, v in resp.headers.items():
            if k.lower() not in HOP_BY_HOP:
                self.send_header(k, v)
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

        # Stream through, keeping only a small tail so usage can be recovered
        # from the final SSE chunk without buffering the whole response.
        #
        # read1() rather than read(): read() blocks until the full buffer is
        # filled, which coalesces many small SSE events into one forwarded
        # write and destroys inter-token timing (observed as a 700x inflated
        # decode rate when benchmarking through the proxy). read1() returns as
        # soon as any data is available, preserving streaming semantics.
        reader = getattr(resp, "read1", None) or resp.read
        tail = b""
        try:
            while True:
                buf = reader(8192)
                if not buf:
                    break
                self.wfile.write(b"%x\r\n" % len(buf) + buf + b"\r\n")
                self.wfile.flush()
                tail = (tail + buf)[-16384:]
            self.wfile.write(b"0\r\n\r\n")
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            resp.close()

        if record is not None:
            m = _USAGE_RE.findall(tail.decode("utf-8", "replace"))
            if m:
                record["prompt_tokens"] = int(m[-1])
            self.server.emit(record)

    do_GET = _proxy
    do_POST = _proxy
    do_DELETE = _proxy
    do_PUT = _proxy

    def _analyze(self, raw):
        try:
            body = json.loads(raw)
        except ValueError:
            return None
        flat = flatten_messages(body)
        with _state_lock:
            _seq["n"] += 1
            seq = _seq["n"]
            prev = _prev_prompt["text"]
            _prev_prompt["text"] = flat
        lcp = longest_common_prefix(prev, flat) if prev else 0
        rec = {
            "seq": seq,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "model": body.get("model"),
            "prompt_chars": len(flat),
            "prev_prompt_chars": len(prev) if prev else 0,
            "lcp_chars": lcp,
            "lcp_pct": round(100.0 * lcp / len(flat), 1) if flat else 0.0,
            "new_chars": len(flat) - lcp,
            "n_messages": len(body.get("messages") or []),
            "head_200": flat[:200],
            "tail_200": flat[-200:],
        }
        return rec


class Proxy(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, addr, upstream, log_path, timeout_s):
        super().__init__(addr, Handler)
        self.upstream = upstream
        self.log_path = log_path
        self.timeout_s = timeout_s
        self._log_lock = threading.Lock()

    def emit(self, rec):
        with self._log_lock:
            with open(self.log_path, "a") as f:
                f.write(json.dumps(rec) + "\n")
        if rec["seq"] == 1:
            note = "first request (no baseline)"
        elif rec["lcp_pct"] >= 90:
            note = "cache-friendly"
        elif rec["lcp_pct"] >= 50:
            note = "PARTIAL - prefix drifting"
        else:
            note = "BROKEN - prefix unstable, expect full prefill every turn"
        print(
            "[tap #%d] prompt=%s chars (%s tok) lcp=%.1f%% new=%d chars  %s"
            % (
                rec["seq"],
                rec["prompt_chars"],
                rec.get("prompt_tokens", "?"),
                rec["lcp_pct"],
                rec["new_chars"],
                note,
            ),
            file=sys.stderr,
        )


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--listen", type=int, default=8090)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--upstream", default="http://127.0.0.1:8083",
                    help="real engine base (no /v1 suffix; paths pass through)")
    ap.add_argument("--log", default=None,
                    help="JSONL log path (default: "
                         "~/ai/artifacts/llm-tap/session-<stamp>.jsonl)")
    ap.add_argument("--timeout", type=float, default=1800.0)
    args = ap.parse_args()

    if args.log:
        log_path = Path(os.path.expanduser(args.log))
    else:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        log_path = Path(os.path.expanduser(
            "~/ai/artifacts/llm-tap/session-%s.jsonl" % stamp))
    log_path.parent.mkdir(parents=True, exist_ok=True)

    srv = Proxy((args.host, args.listen), args.upstream, log_path, args.timeout)
    print("llm-tap %s:%d -> %s" % (args.host, args.listen, args.upstream),
          file=sys.stderr)
    print("logging to %s" % log_path, file=sys.stderr)
    print("point opencode at http://%s:%d/v1" % (args.host, args.listen),
          file=sys.stderr)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
