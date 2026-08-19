"""Benchmark an OpenAI-compatible local LLM server, measuring prefill honestly.

Replaces qwen38-bench.py / omlx-context-probe.py, both of which produced
invalid prompt-processing numbers. Their shared root cause: `build_prompt()`
was fully deterministic, so every run after the first hit the engine's prefix
cache. omlx-context-probe.py's docstring claimed it sent "a fresh
(non-SSD-cached) prefill" while doing the exact opposite. That is why the old
report shows TTFT of 0.007-0.034s at 32k context (~1e6 prompt tok/s, which is
impossible) alongside a genuine cold prefill of 42,440 tokens in 454.9s
(~93 tok/s).

They also computed prefill tok/s from `len(prompt) // 4` rather than the
server's own `usage.prompt_tokens`, which is how a "32k" run was reported
while actually sending 42k tokens.

What this script does differently:

  * Token counts come from the server (`stream_options.include_usage`), never
    from a chars/4 guess.
  * Cold runs prepend a unique random nonce at the HEAD of the prompt, so no
    stored prefix can match. Engine-agnostic: works whether the cache lives on
    disk (oMLX) or in RAM.
  * Prefill and decode are measured separately, in separate requests.
  * MFU is computed, which is the number that decides whether prefill tuning
    is worth doing at all on this hardware.
  * Warm mode replays an identical prompt and reports cache_speedup_x against
    its own cold first pass, so cache behaviour is measured on purpose rather
    than contaminating cold numbers.
  * Two assertions reject bad data instead of publishing it (see validate()).
    The contamination bound applies to cold runs only - in warm mode a fast
    prefill is the desired result.
  * Server refusals (context-ceiling probes) are recorded as REJECTED with the
    server's message, distinct from client-side TIMEOUT.

Usage
-----
  bench-llm --endpoint http://127.0.0.1:8083/v1 --tag omlx-qwen38
  bench-llm --endpoint http://127.0.0.1:8081/v1 --tag mtplx --mode warm

Output: JSON per run plus a markdown summary in
~/ai/artifacts/local-llm-bench/.
"""

import argparse
import json
import os
import random
import re
import string
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

# A run implying more than this many prompt tok/s on a ~27B dense model is not
# physically possible on Apple Silicon, so it is a cache hit being mistaken for
# a prefill. This is the exact failure that invalidated the previous report.
CONTAMINATION_TOK_S = 500.0

# Rows whose server-reported prompt_tokens deviate from target by more than
# this are excluded from summaries rather than mislabelled.
TOKEN_TOLERANCE = 0.10

CTX_ALIASES = {"k": 1024, "m": 1024 * 1024}


def parse_ctx(spec):
    """Parse "4k,16k,32768" into a list of ints."""
    out = []
    for part in spec.split(","):
        part = part.strip().lower()
        if not part:
            continue
        mult = 1
        if part[-1] in CTX_ALIASES:
            mult = CTX_ALIASES[part[-1]]
            part = part[:-1]
        out.append(int(float(part) * mult))
    return out


# ---------------------------------------------------------------------------
# Prompt construction
# ---------------------------------------------------------------------------

# Deterministic natural-ish filler. Real words (rather than the old script's
# repeated 99-char letter run) keep the chars-per-token ratio stable and
# predictable across tokenizers.
_WORDS = (
    "system module handler request context buffer pointer thread session "
    "record value index mapping segment channel stream packet header client "
    "server process memory kernel device driver socket filter parser encoder "
    "decoder monitor scheduler allocator registry adapter service worker "
    "queue cache token window layer matrix vector tensor gradient weight"
).split()


def _filler(n_chars, rng):
    parts = []
    total = 0
    while total < n_chars:
        w = rng.choice(_WORDS)
        parts.append(w)
        total += len(w) + 1
    return " ".join(parts)


def make_nonce(rng, n_words=64):
    """A unique block for the HEAD of the prompt, to defeat prefix caching."""
    words = []
    for _ in range(n_words):
        words.append("".join(rng.choice(string.ascii_lowercase) for _ in range(9)))
    return "SESSION-NONCE " + " ".join(words)


def build_prompt(target_tokens, chars_per_token, nonce=None, body_seed=1234):
    """Build a prompt of approximately target_tokens.

    body_seed is fixed so the body is identical across runs; only the nonce
    varies. That lets --mode warm replay an identical prompt on purpose, while
    --mode cold guarantees a fresh prefix.
    """
    head = "You are a careful assistant. Read the reference text and answer.\n"
    if nonce:
        head += nonce + "\n"
    tail = (
        "\n---END REFERENCE---\n\n"
        "Question: Summarize the key theme of the reference in one sentence.\n"
        "Answer:"
    )
    overhead = len(head) + len(tail) + len("\n---REFERENCE---\n")
    body_chars = max(1, int(target_tokens * chars_per_token) - overhead)
    rng = random.Random(body_seed)
    return head + "\n---REFERENCE---\n" + _filler(body_chars, rng) + tail


# ---------------------------------------------------------------------------
# HTTP (stdlib only - no openai SDK dependency)
# ---------------------------------------------------------------------------


def _post(endpoint, path, payload, timeout):
    url = endpoint.rstrip("/") + path
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer local",
        },
    )
    return urllib.request.urlopen(req, timeout=timeout)


def discover_model(endpoint, timeout=30):
    """Resolve the model id, refusing to guess when the choice is ambiguous.

    oMLX is served with `--model-dir <dir>`, i.e. it offers every model in that
    directory and picks per request. Silently taking data[0] means benchmarking
    whichever model happens to sort first - e.g. an old
    Huihui-...-abliterated-... build left on disk - and labelling the results
    with whatever tag was passed. That is the same class of error as the
    cache-contaminated numbers this tool was written to replace, so it is a
    hard failure rather than a warning.
    """
    url = endpoint.rstrip("/") + "/models"
    req = urllib.request.Request(url, headers={"Authorization": "Bearer local"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = json.load(r)
    items = data.get("data") or []
    if not items:
        raise SystemExit("no models reported by " + url)
    if len(items) > 1:
        listing = "\n".join("  --model %s" % i["id"] for i in items)
        raise SystemExit(
            "%d models are being served; refusing to guess which one to "
            "benchmark.\nRe-run with one of:\n%s" % (len(items), listing)
        )
    return items[0]["id"]


def stream_chat(endpoint, model, prompt, max_tokens, timeout):
    """Stream a completion. Returns a dict of timings and server token counts.

    ttft_s is measured to the first chunk carrying actual content, not to the
    first chunk of any kind (many servers emit a role-only delta immediately,
    which would understate prefill time).
    """
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0.0,
        "stream": True,
        "stream_options": {"include_usage": True},
    }
    t0 = time.perf_counter()
    t_first_chunk = None
    t_first_content = None
    t_last = None
    usage = None
    stream_error = None
    n_content_chunks = 0

    resp = _post(endpoint, "/chat/completions", payload, timeout)
    with resp:
        for raw in resp:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            body = line[5:].strip()
            if body == "[DONE]":
                break
            try:
                chunk = json.loads(body)
            except ValueError:
                continue
            now = time.perf_counter() - t0
            if t_first_chunk is None:
                t_first_chunk = now
            if chunk.get("usage"):
                usage = chunk["usage"]
            # Servers may refuse in-stream with HTTP 200 + an error payload
            # (oMLX does this for prefill-memory-guard rejections), which no
            # HTTP-level handler would ever see.
            if chunk.get("error"):
                err = chunk["error"]
                stream_error = (err.get("message") if isinstance(err, dict)
                                else str(err))
            for ch in chunk.get("choices") or []:
                delta = ch.get("delta") or {}
                text = delta.get("content") or ""
                text += delta.get("reasoning_content") or ""
                if text:
                    if t_first_content is None:
                        t_first_content = now
                    t_last = now
                    n_content_chunks += 1

    total = time.perf_counter() - t0
    return {
        "ttft_s": t_first_content if t_first_content is not None else t_first_chunk,
        "t_first_chunk_s": t_first_chunk,
        "t_last_s": t_last,
        "total_s": total,
        "usage": usage,
        "stream_error": stream_error,
        "n_content_chunks": n_content_chunks,
    }


# ---------------------------------------------------------------------------
# Memory sampling
# ---------------------------------------------------------------------------


def find_server_pid(endpoint):
    try:
        port = urlparse(endpoint).port
        if not port:
            return None
        out = subprocess.run(
            ["lsof", "-ti", "TCP:%d" % port, "-sTCP:LISTEN"],
            capture_output=True,
            text=True,
        ).stdout.strip()
        pids = [int(p) for p in out.splitlines() if p.strip().isdigit()]
        return pids[0] if pids else None
    except Exception:
        return None


_UNITS = {"kb": 1e-6, "mb": 1e-3, "gb": 1.0, "tb": 1e3}


def phys_footprint_gb(pid):
    """Current phys_footprint in GB, or None.

    phys_footprint (not ps RSS) is the only figure that accounts for Metal
    unified-memory heaps, which hold the model weights.
    """
    try:
        out = subprocess.run(
            ["/usr/bin/footprint", "-p", str(pid)],
            capture_output=True,
            text=True,
            timeout=30,
        ).stdout
    except Exception:
        return None
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("phys_footprint:"):
            parts = line.split(":", 1)[1].strip().split()
            if not parts:
                return None
            try:
                val = float(parts[0])
            except ValueError:
                return None
            unit = parts[1].lower() if len(parts) > 1 else "gb"
            return round(val * _UNITS.get(unit, 1.0), 2)
    return None


class MemorySampler(threading.Thread):
    """Polls phys_footprint during a run so peak is observed, not spot-checked.

    The previous report sampled once before and once after, at 4k and 8k only,
    and concluded oMLX had zero context growth - which its own ceiling probe
    (26 -> 33 GB from 42k to 148k tokens) contradicts.
    """

    def __init__(self, pid, interval=2.0):
        super().__init__(daemon=True)
        self.pid = pid
        self.interval = interval
        self._stop = threading.Event()
        self.samples = []

    def run(self):
        while not self._stop.is_set():
            v = phys_footprint_gb(self.pid)
            if v is not None:
                self.samples.append(v)
            self._stop.wait(self.interval)

    def stop(self):
        self._stop.set()
        self.join(timeout=10)
        return {
            "min_gb": min(self.samples) if self.samples else None,
            "max_gb": max(self.samples) if self.samples else None,
            "n_samples": len(self.samples),
        }


# ---------------------------------------------------------------------------
# Measurement
# ---------------------------------------------------------------------------


def calibrate(endpoint, model, timeout):
    """Measure this tokenizer's chars-per-token on the filler text.

    Without this, a "32k" target silently sends 42k tokens - exactly what
    happened in the previous report.
    """
    rng = random.Random(99)
    probe = _filler(8000, rng)
    r = stream_chat(endpoint, model, probe, 1, timeout)
    usage = r.get("usage") or {}
    ptok = usage.get("prompt_tokens")
    if not ptok:
        print("WARNING: server did not report prompt_tokens; "
              "falling back to 4.0 chars/token and rows may be invalid",
              file=sys.stderr)
        return 4.0
    cpt = len(probe) / float(ptok)
    print("calibration: %d chars -> %d tokens (%.3f chars/token)"
          % (len(probe), ptok, cpt))
    return cpt


def classify_error(e):
    """Distinguish a server refusal from a client-side timeout.

    Context-ceiling probes are expected to end in refusals ("Prefill capacity
    rejected ... exceeds prefill safety cap"), which arrive as HTTP 4xx/5xx.
    Labelling those TIMEOUT would hide the very thing being measured.
    """
    if isinstance(e, urllib.error.HTTPError):
        try:
            body = e.read().decode("utf-8", "replace")[:400]
        except Exception:
            body = ""
        return "REJECTED", "HTTP %s: %s" % (e.code, body or str(e)[:200])
    return "TIMEOUT", "%s: %s" % (type(e).__name__, str(e)[:200])


def validate(target, prompt_tokens, prefill_tok_s, mode="cold"):
    """Return (status, notes). This is the heart of the rewrite.

    The contamination bound applies to COLD runs only. In warm mode a prefill
    rate far above the dense-model bound is the whole point - it means the
    prefix cache engaged - so flagging it would mark success as failure.
    """
    notes = []
    status = "OK"
    if prompt_tokens:
        dev = abs(prompt_tokens - target) / float(target)
        if dev > TOKEN_TOLERANCE:
            status = "INVALID"
            notes.append(
                "prompt_tokens %d deviates %.1f%% from target %d"
                % (prompt_tokens, dev * 100, target)
            )
    else:
        status = "INVALID"
        notes.append("server reported no prompt_tokens")

    if mode == "cold":
        if prefill_tok_s and prefill_tok_s > CONTAMINATION_TOK_S:
            status = "INVALID"
            notes.append(
                "cache contamination suspected: %.0f prompt tok/s exceeds the "
                "%.0f tok/s plausibility bound for a dense model"
                % (prefill_tok_s, CONTAMINATION_TOK_S)
            )
    else:
        if prefill_tok_s and prefill_tok_s < CONTAMINATION_TOK_S:
            notes.append(
                "no cache speedup: %.0f prompt tok/s is within cold-prefill "
                "range, so the prefix cache did not engage"
                % prefill_tok_s
            )
    return status, notes


def measure_ctx(args, model, ctx, chars_per_token, sampler_pid):
    rng = random.Random()
    rec = {"context_target": ctx, "mode": args.mode}

    # A first pass is only worth paying for in warm mode, where it IS the cold
    # baseline the cache speedup is measured against.
    #
    # It was originally a JIT-compile warmup for cold mode too, on the
    # assumption that kernel compilation was a large one-time cost per context
    # length. Measurement killed that assumption: the warmup takes the same
    # time as the run it precedes (34.17s vs 34.17s at 4k, 722.5s vs 727.4s at
    # 64k), i.e. it is just a second full prefill and JIT is negligible. In
    # cold mode it doubles runtime for nothing, so it is now opt-in.
    prompt = build_prompt(ctx, chars_per_token, nonce=make_nonce(rng))
    first_pass = args.mode == "warm" or args.jit_warmup

    if first_pass:
        # In warm mode the measured request must replay this exact prompt.
        # In cold mode use a different nonce so the measured prefix stays cold.
        warm_prompt = prompt if args.mode == "warm" else build_prompt(
            ctx, chars_per_token, nonce=make_nonce(rng))
        t0 = time.perf_counter()
        try:
            stream_chat(args.endpoint, model, warm_prompt, 1, args.timeout)
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            rec["first_pass_s"] = round(time.perf_counter() - t0, 2)
            rec["status"], rec["error"] = classify_error(e)
            return rec
        key = "cold_baseline_s" if args.mode == "warm" else "jit_warmup_s"
        rec[key] = round(time.perf_counter() - t0, 2)

    sampler = MemorySampler(sampler_pid) if sampler_pid else None
    if sampler:
        sampler.start()

    # --- prefill: max_tokens=1 isolates prompt processing ---
    try:
        pf = stream_chat(args.endpoint, model, prompt, 1, args.timeout)
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        if sampler:
            rec["memory"] = sampler.stop()
        rec["status"], rec["error"] = classify_error(e)
        return rec

    if pf.get("stream_error"):
        if sampler:
            rec["memory"] = sampler.stop()
        rec["status"] = "REJECTED"
        rec["error"] = pf["stream_error"][:400]
        return rec

    usage = pf.get("usage") or {}
    ptok = usage.get("prompt_tokens")
    ttft = pf.get("ttft_s")
    prefill_tok_s = (ptok / ttft) if (ptok and ttft) else None

    rec["prompt_tokens"] = ptok
    rec["ttft_s"] = round(ttft, 3) if ttft else None
    rec["prefill_tok_s"] = round(prefill_tok_s, 1) if prefill_tok_s else None
    if ptok and ttft:
        # Prefill FLOPs = dense term + attention term.
        #
        # The dense term (2 x params x tokens) is all that matters at small
        # context. The attention term grows as n^2 and is emphatically NOT
        # negligible at long context: for this model it is ~3% of the total at
        # 4k but ~40% at 94k. Omitting it (as this script originally did) makes
        # MFU look like it collapses with context - 83% at 4k down to 28% at
        # 94k - when much of that "collapse" is just unaccounted work.
        #
        # Per full-attention layer: QK^T and AV are each 2 x n^2 x heads x
        # head_dim FLOPs. Layers using linear attention are excluded, since
        # their cost is linear in n and already close enough to the dense term.
        dense = 2.0 * args.params * ptok
        attn = 4.0 * (ptok ** 2) * args.attn_heads * args.attn_head_dim \
            * args.attn_full_layers
        total = dense + attn
        rec["mfu_pct"] = round(100.0 * total / (ttft * args.peak_flops), 1)
        rec["mfu_dense_only_pct"] = round(
            100.0 * dense / (ttft * args.peak_flops), 1)
        rec["attn_share_pct"] = round(100.0 * attn / total, 1)

    # --- decode: separate request, same prompt (now warm), longer generation ---
    try:
        ev = stream_chat(args.endpoint, model, prompt, args.max_tokens, args.timeout)
        eusage = ev.get("usage") or {}
        ctok = eusage.get("completion_tokens")
        if ctok and ev.get("t_last_s") and ev.get("ttft_s") and ctok > 1:
            span = ev["t_last_s"] - ev["ttft_s"]
            if span > 0:
                rec["decode_tok_s"] = round((ctok - 1) / span, 2)
        rec["completion_tokens"] = ctok
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        rec["decode_error"] = "%s: %s" % (type(e).__name__, str(e)[:200])

    if sampler:
        rec["memory"] = sampler.stop()

    # Cache speedup comes free in warm mode: the first pass was the cold
    # prefill of this same prompt, so no separate cold run is needed.
    base = rec.get("cold_baseline_s")
    if base and ttft:
        rec["cache_speedup_x"] = round(base / ttft, 1)

    rec["status"], rec["notes"] = validate(ctx, ptok, prefill_tok_s, args.mode)
    return rec


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------


def markdown(results):
    lines = []
    lines.append("# bench-llm: %s" % results["tag"])
    lines.append("")
    lines.append("- endpoint: `%s`" % results["endpoint"])
    lines.append("- model: `%s`" % results["model"])
    lines.append("- mode: **%s**" % results["mode"])
    lines.append("- timestamp: %s" % results["timestamp"])
    lines.append(
        "- peak FLOPS assumed: %.3g (ESTIMATE - MFU is only as good as this)"
        % results["peak_flops"]
    )
    lines.append("- params assumed: %.3g" % results["params"])
    lines.append("- model idle footprint: %s GB" % results.get("idle_footprint_gb"))
    lines.append("")
    warm = results["mode"] == "warm"
    last = "cold base s | speedup" if warm else "MFU %"
    header = (
        "| ctx target | prompt tok | TTFT s | prefill tok/s | "
        "decode tok/s | peak GB | %s | status |" % last
    )
    lines.append(header)
    lines.append("|---|---|---|---|---|---|---|---|" + ("---|" if warm else ""))
    for r in results["runs"]:
        mem = r.get("memory") or {}
        tail = ("%s | %sx" % (r.get("cold_baseline_s", "-"),
                              r.get("cache_speedup_x", "-"))
                if warm else str(r.get("mfu_pct", "-")))
        lines.append(
            "| %s | %s | %s | %s | %s | %s | %s | %s |"
            % (
                r.get("context_target"),
                r.get("prompt_tokens", "-"),
                r.get("ttft_s", "-"),
                r.get("prefill_tok_s", "-"),
                r.get("decode_tok_s", "-"),
                mem.get("max_gb", "-"),
                tail,
                r.get("status", "-"),
            )
        )
    lines.append("")
    bad = [r for r in results["runs"] if r.get("status") != "OK"]
    if bad:
        lines.append("## Rejected rows")
        lines.append("")
        for r in bad:
            for n in r.get("notes") or [r.get("error", "unknown")]:
                lines.append("- ctx=%s: %s" % (r.get("context_target"), n))
        lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--endpoint", required=True,
                    help="OpenAI-compatible base URL, e.g. http://127.0.0.1:8083/v1")
    ap.add_argument("--tag", required=True, help="label for output files")
    ap.add_argument("--model", default=None, help="model id (default: first served)")
    ap.add_argument("--mode", choices=["cold", "warm"], default="cold",
                    help="cold: fresh nonce per run (measures real prefill). "
                         "warm: replay identical prompt (measures cache hit).")
    ap.add_argument("--ctx", default="4k,16k,32k,64k,128k",
                    help="comma-separated context targets")
    ap.add_argument("--max-tokens", type=int, default=128,
                    help="tokens to generate for the decode measurement")
    ap.add_argument("--params", type=float, default=27e9,
                    help="model parameter count, for MFU")
    ap.add_argument("--peak-flops", type=float, default=8e12,
                    help="GPU peak FLOPS estimate (M4 Pro default ~8e12)")
    # Qwen3.8-27B defaults, from its config.json: 24 heads, head_dim 256, and
    # layer_types repeating [linear, linear, linear, full] over 64 layers, so
    # only 16 layers do quadratic attention.
    ap.add_argument("--attn-heads", type=int, default=24)
    ap.add_argument("--attn-head-dim", type=int, default=256)
    ap.add_argument("--attn-full-layers", type=int, default=16,
                    help="layers doing full (quadratic) attention, not linear")
    ap.add_argument("--timeout", type=float, default=1800.0,
                    help="per-request timeout in seconds")
    ap.add_argument("--assume-tok-s", type=float, default=50.0,
                    help="pessimistic prefill rate used only to pre-check that "
                         "--timeout is large enough for the requested contexts")
    ap.add_argument("--jit-warmup", action="store_true",
                    help="cold mode only: run a discarded same-length prefill "
                         "first. Measured JIT cost is negligible (the warmup "
                         "takes as long as the run), so this just doubles "
                         "runtime; off by default.")
    ap.add_argument("--server-pid", type=int, default=None,
                    help="override server pid for footprint sampling")
    ap.add_argument("--out-dir",
                    default=os.path.expanduser("~/ai/artifacts/local-llm-bench"))
    args = ap.parse_args()

    model = args.model or discover_model(args.endpoint)
    pid = args.server_pid or find_server_pid(args.endpoint)
    print("endpoint=%s model=%s pid=%s mode=%s" % (args.endpoint, model, pid, args.mode))
    if pid is None:
        print("WARNING: could not find server pid; memory will not be sampled",
              file=sys.stderr)

    # A client-side timeout does NOT cancel the request server-side: oMLX keeps
    # prefilling and the orphan then contends with every later measurement.
    # Refuse up front rather than silently poisoning the run. The floor is
    # deliberately pessimistic (prefill tok/s falls with context: ~123 at 4k,
    # ~86 at 64k, ~65 at 125k).
    targets = parse_ctx(args.ctx)
    slowest = max(targets)
    needed = slowest / args.assume_tok_s
    if needed > args.timeout:
        raise SystemExit(
            "--timeout %.0fs is too short for ctx=%d: at a pessimistic "
            "%.0f prompt tok/s that prefill needs ~%.0fs (%.0f min).\n"
            "A client timeout does not cancel the server-side request, so the "
            "orphan would contend with later rows.\n"
            "Re-run with --timeout %d"
            % (args.timeout, slowest, args.assume_tok_s, needed, needed / 60,
               int(needed * 1.5))
        )

    chars_per_token = calibrate(args.endpoint, model, args.timeout)

    idle = None
    if pid:
        time.sleep(2)
        idle = phys_footprint_gb(pid)
        print("model idle footprint: %s GB" % idle)

    results = {
        "tag": args.tag,
        "endpoint": args.endpoint,
        "model": model,
        "mode": args.mode,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "server_pid": pid,
        "chars_per_token": round(chars_per_token, 3),
        "params": args.params,
        "peak_flops": args.peak_flops,
        "idle_footprint_gb": idle,
        "runs": [],
    }

    for ctx in parse_ctx(args.ctx):
        print("\n--- ctx target %d ---" % ctx)
        rec = measure_ctx(args, model, ctx, chars_per_token, pid)
        results["runs"].append(rec)
        print(json.dumps(rec, indent=2))

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9._-]", "_", args.tag)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    base = "%s-%s-%s" % (safe, args.mode, stamp)
    (out_dir / (base + ".json")).write_text(json.dumps(results, indent=2))
    (out_dir / (base + ".md")).write_text(markdown(results))
    print("\nWrote %s.{json,md} in %s" % (base, out_dir))
    print()
    print(markdown(results))

    if any(r.get("status") != "OK" for r in results["runs"]):
        print("\nSome rows were rejected - see 'Rejected rows' above.",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
