#!/usr/bin/env python3
"""RETRACTED - superseded by bench-llm. Its prefill numbers are invalid.

Do not run this to measure prompt processing, and do not cite figures it
produced. Two defects, both confirmed by reading the code below:

  1. `build_prompt()` is fully deterministic (its own docstring advertises
     "cacheable across runs"), so every run after the first hit the engine's
     prefix cache. The reported TTFT is a cache-hit latency, not a prefill.
     This is why the 2026-08-19 report shows 0.007-0.034s TTFT at 32k context
     (~1e6 prompt tok/s, physically impossible) next to a genuine cold prefill
     of 42,440 tokens in 454.9s (~93 tok/s).
  2. `prefill_tok_s` is computed from `count_tokens_estimate()` = len//4 rather
     than the server's `usage.prompt_tokens`, which is how a run labelled
     "ctx=32k" actually sent ~42k tokens.

The memory methodology is also weak: `model_idle_gb` is sampled after a warmup
request, so for engines that pre-allocate a paged-KV arena it measures
model+arena, and "context growth" was only ever tested over 4k->8k.

The `--ssd-cache` mode is the one part that remains sound (it restarts the
server between passes), though it does not clear the cache before pass 1.

Kept only so the previous report's provenance stays auditable.
See docs/superpowers/specs/2026-08-19-local-llm-prefill-design.md.

---

Original docstring follows.

Benchmark Qwen 3.8 local inference servers (mtplx / oMLX).

Correctly separates the two things people actually care about:

  * MEMORY  -> the MODEL footprint (idle, no context) vs the CONTEXT footprint
               (after filling the KV cache). Uses `phys_footprint` via the
               macOS `footprint` tool (real unified-memory accounting that
               includes Metal heaps), NOT process RSS (which undercounts
               Metal-allocated weights, e.g. mtplx).

  * PREfill -> time to first token with max_tokens=1 isolates prefill
               (processing the whole prompt -> 1 token). prefill tok/s =
               context_tokens / TTFT.

  * EVAL    -> decode throughput after prefill (chars/4 per sec, incl.
               reasoning tokens).

Modes
-----
default:
  For each context size, measures model footprint (idle), context footprint
  (after prefill), prefill tok/s, and eval tok/s.

--ssd-cache:
  Tests oMLX's SSD-tiered KV cache (prefill, restart, re-measure same prompt).

Usage
-----
  ai-bench --base-url <url> --model <id> --tag <label> \
           [--context 4096 32768] [--tokens 64]

  ai-bench --ssd-cache --omlx-bin <path> --model-dir <dir> --model <id> \
           --tag omlx-ssd [--context 32768] [--port 8083]

Output: JSON per tag to ~/ai/artifacts/qwen38-bench/ (and stdout).
"""

import argparse
import json
import os
import signal
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

import openai


def build_prompt(n_tokens: int) -> str:
    """A deterministic ~n_tokens prompt (repeatable, cacheable across runs)."""
    word = "loremipsumdolorsitametconsectetur"
    per_token = 4
    chunk = word * 3  # ~78 chars
    reps = max(1, (n_tokens * per_token) // len(chunk))
    body = " ".join(chunk for _ in range(reps))
    return (
        "You are a careful assistant. Please read the following reference text and "
        "answer the question at the end precisely.\n\n---REFERENCE---\n"
        + body
        + "\n---END REFERENCE---\n\nQuestion: Summarize the key theme of the reference in one sentence.\nAnswer:"
    )


def count_tokens_estimate(s: str) -> int:
    return max(1, len(s) // 4)


def find_server_pids(base_url: str) -> list:
    try:
        from urllib.parse import urlparse

        port = urlparse(base_url).port or 8000
        out = subprocess.run(
            ["lsof", "-ti", f"TCP:{port}", "-sTCP:LISTEN"],
            capture_output=True,
            text=True,
        ).stdout.strip()
        return [int(p) for p in out.splitlines() if p.strip().isdigit()]
    except Exception:
        return []


def phys_footprint_gb(pid: int):
    """Real unified-memory footprint (GB) via macOS `footprint` tool.

    Returns (current_gb, peak_gb). Captures Metal heaps that `ps` RSS misses.
    The tool reports values in human units like "17 GB" / "512 MB".
    """
    _UNITS = {"kb": 1e-6, "mb": 1e-3, "gb": 1.0, "tb": 1e3}

    def parse(s):
        try:
            parts = s.strip().split()
            if not parts:
                return None
            val = float(parts[0])
            unit = parts[1].lower() if len(parts) > 1 else "gb"
            return round(val * _UNITS.get(unit, 1.0), 2)
        except Exception:
            return None

    try:
        out = subprocess.run(
            ["/usr/bin/footprint", "-p", str(pid)],
            capture_output=True,
            text=True,
            timeout=30,
        ).stdout
        cur = peak = None
        for line in out.splitlines():
            line = line.strip()
            if line.startswith("phys_footprint:"):
                cur = parse(line.split(":", 1)[1])
            elif line.startswith("phys_footprint_peak:"):
                peak = parse(line.split(":", 1)[1])
        return cur, peak
    except Exception:
        return None, None


def sample_rss_mb(pid: int) -> float:
    try:
        out = subprocess.run(
            ["ps", "-o", "rss=", "-p", str(pid)],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        if out:
            return int(out) / 1024.0
    except Exception:
        pass
    return 0.0


def wait_server(base_url: str, timeout: float = 300.0) -> None:
    import urllib.request

    probe = base_url.rstrip("/")
    if not probe.endswith("/v1"):
        probe += "/v1"
    probe += "/models"
    start = time.time()
    while time.time() - start < timeout:
        try:
            urllib.request.urlopen(probe, timeout=2)
            return
        except Exception:
            time.sleep(1.0)
    raise TimeoutError(f"server at {base_url} not ready after {timeout}s")


def _stream_gen(client, model, prompt, n_gen):
    """Yield (elapsed_s, char_delta) for each streamed chunk."""
    t0 = time.perf_counter()
    stream = client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": prompt}],
        max_tokens=n_gen,
        temperature=0.0,
        stream=True,
    )
    for chunk in stream:
        t = time.perf_counter() - t0
        delta = chunk.choices[0].delta
        txt = ((delta.content if delta else "") or "")
        if delta is not None:
            txt += (getattr(delta, "reasoning_content", None) or "")
        yield t, len(txt)


def measure_prefill(client, model, prompt):
    """Prefill-only: max_tokens=1. Returns {ttft_s, prefill_tok_s}."""
    t0 = time.perf_counter()
    first = None
    try:
        stream = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=1,
            temperature=0.0,
            stream=True,
        )
        for chunk in stream:
            t = time.perf_counter() - t0
            if first is None:
                first = t
            if chunk.choices[0].finish_reason:
                break
    except Exception as e:
        return {"error": str(e)}
    dur = time.perf_counter() - t0
    return {
        "ttft_s": round(first, 4) if first else None,
        "duration_s": round(dur, 3),
    }


def measure_eval(client, model, prompt, n_gen):
    """Decode after prefill. Returns tok/s (chars/4) + TTFT."""
    t0 = time.perf_counter()
    first = None
    n_out = 0
    n_chunks = 0
    try:
        for t, d in _stream_gen(client, model, prompt, n_gen):
            if first is None:
                first = t
            n_out += d
            n_chunks += 1
    except Exception as e:
        return {"error": str(e)}
    dur = time.perf_counter() - t0
    tok_s = (n_out / 4.0) / dur if dur > 0 else 0.0
    return {
        "ttft_s": round(first, 4) if first else None,
        "duration_s": round(dur, 3),
        "out_chars": n_out,
        "est_out_tokens": round(n_out / 4.0, 1),
        "est_tok_s": round(tok_s, 2),
        "n_chunks": n_chunks,
    }


def run_default(args) -> dict:
    client = openai.OpenAI(base_url=args.base_url, api_key="local")
    pids = find_server_pids(args.base_url)
    pid = pids[0] if pids else None
    if pid:
        print(f"[{args.tag}] serving pid(s): {pids}")

    results = {
        "mode": "default",
        "tag": args.tag,
        "base_url": args.base_url,
        "model": args.model,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "server_pids": pids,
        "memory": {},
        "runs": [],
    }

    # model footprint: idle, before any context (only if model already resident)
    if pid:
        # ensure the model is resident first (tiny request) so idle = model only
        try:
            _stream_gen(client, args.model, "hi", 1)
        except Exception:
            pass
        time.sleep(1)
        cur, peak = phys_footprint_gb(pid)
        results["memory"]["model_idle_gb"] = cur
        results["memory"]["model_idle_peak_gb"] = peak
        print(f"[{args.tag}] MODEL footprint (idle): {cur} GB (peak {peak} GB)")

    for ctx in args.context:
        prompt = build_prompt(ctx)
        est = count_tokens_estimate(prompt)
        print(f"\n[{args.tag}] context target={ctx} (approx {est} tokens)")

        run = {"context_target": ctx, "prompt_approx_tokens": est}

        # Prefill (max_tokens=1)
        pf = measure_prefill(client, args.model, prompt)
        run["prefill"] = pf
        if "error" in pf:
            print(f"[{args.tag}] ctx={ctx} prefill ERROR {pf['error']}")
        else:
            tok_s = est / pf["ttft_s"] if pf["ttft_s"] else 0
            pf["prefill_tok_s"] = round(tok_s, 1)
            print(
                f"[{args.tag}] ctx={ctx} PREFILL ttft={pf['ttft_s']}s "
                f"({pf['prefill_tok_s']} tok/s)"
            )

        # Context footprint (after prefill fills KV)
        if pid:
            time.sleep(1)
            cur, peak = phys_footprint_gb(pid)
            run["context_footprint_gb"] = cur
            run["context_footprint_peak_gb"] = peak
            base = results["memory"].get("model_idle_gb")
            if base and cur:
                run["context_growth_gb"] = round(cur - base, 2)
                print(
                    f"[{args.tag}] ctx={ctx} CONTEXT footprint: {cur} GB "
                    f"(growth +{run['context_growth_gb']} GB)"
                )

        # Eval (decode after prefill)
        ev = measure_eval(client, args.model, prompt, args.tokens)
        run["eval"] = ev
        if "error" in ev:
            print(f"[{args.tag}] ctx={ctx} eval ERROR {ev['error']}")
        else:
            print(f"[{args.tag}] ctx={ctx} EVAL ttft={ev['ttft_s']}s tok/s~{ev['est_tok_s']}")

        results["runs"].append(run)
    return results


def run_ssd_cache(args) -> dict:
    """Test oMLX SSD KV cache: prefill, restart, re-measure TTFT."""
    if not args.omlx_bin or not args.model_dir:
        raise SystemExit("--ssd-cache requires --omlx-bin and --model-dir")

    base_url = args.base_url or f"http://127.0.0.1:{args.port}/v1"
    ctx = args.context[0]
    prompt = build_prompt(ctx)
    est = count_tokens_estimate(prompt)
    results = {
        "mode": "ssd_cache",
        "tag": args.tag,
        "base_url": base_url,
        "model": args.model,
        "context_target": ctx,
        "prompt_approx_tokens": est,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "passes": {},
    }

    cache_dir = Path(args.omlx_base or os.path.expanduser("~/.omlx")) / "cache"

    def start_server():
        cmd = [
            args.omlx_bin,
            "serve",
            "--model-dir",
            args.model_dir,
            "--host",
            "127.0.0.1",
            "--port",
            str(args.port),
            "--memory-guard-gb",
            str(args.memory_guard_gb),
        ]
        log = Path(os.path.expanduser(args.log_dir)) / f"omlx-ssd-{int(time.time())}.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        f = open(log, "w")
        proc = subprocess.Popen(cmd, stdout=f, stderr=subprocess.STDOUT)
        results.setdefault("log", str(log))
        return proc

    def stop_server(proc):
        if proc is None:
            return
        proc.send_signal(signal.SIGTERM)
        try:
            proc.wait(timeout=30)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()

    def dir_size(path):
        total = 0
        for root, _, files in os.walk(path):
            for f in files:
                try:
                    total += os.path.getsize(os.path.join(root, f))
                except OSError:
                    pass
        return total

    client = openai.OpenAI(base_url=base_url, api_key="local")

    def warm_model():
        try:
            client.chat.completions.create(
                model=args.model,
                messages=[{"role": "user", "content": "hi"}],
                max_tokens=1,
                temperature=0.0,
                stream=False,
            )
        except Exception as e:
            print(f"[{args.tag}] warmup error (continuing): {e}")

    print(f"\n[{args.tag}] PASS 1 (cold prefill, writes SSD cache)")
    proc = start_server()
    try:
        wait_server(base_url, timeout=args.timeout)
        warm_model()
        m1 = measure_prefill(client, args.model, prompt)
        results["passes"]["pass1_cold"] = m1
        print(f"[{args.tag}] pass1 prefill ttft={m1.get('ttft_s')}s")
    finally:
        stop_server(proc)

    size_before = dir_size(cache_dir) if cache_dir.exists() else 0
    results["ssd_cache_bytes_after_pass1"] = size_before
    print(f"[{args.tag}] SSD cache size after pass1: {size_before / 1e6:.1f} MB")

    print(f"\n[{args.tag}] RESTARTING server ...")
    proc = start_server()
    try:
        wait_server(base_url, timeout=args.timeout)
        warm_model()
        m2 = measure_prefill(client, args.model, prompt)
        results["passes"]["pass2_after_restart"] = m2
        print(f"[{args.tag}] pass2 prefill ttft={m2.get('ttft_s')}s")
    finally:
        stop_server(proc)

    size_after = dir_size(cache_dir) if cache_dir.exists() else 0
    results["ssd_cache_bytes_after_pass2"] = size_after

    t1 = (m1 or {}).get("ttft_s")
    t2 = (m2 or {}).get("ttft_s")
    if t1 and t2 and t2 > 0:
        ratio = t1 / t2
        results["ttft_speedup"] = round(ratio, 2)
        results["verdict"] = (
            "SSD cache WORKING (prefill TTFT after restart much lower)"
            if ratio > 1.5
            else "SSD cache NOT clearly working (similar prefill TTFT)"
        )
        print(f"\n[{args.tag}] prefill ttft pass1={t1}s -> pass2={t2}s (x{ratio:.2f})\n[{args.tag}] {results['verdict']}")
    return results


def main():
    ap = argparse.ArgumentParser(description="Benchmark Qwen 3.8 local servers")
    ap.add_argument("--base-url", default=None, help="OpenAI-compatible base URL")
    ap.add_argument("--model", required=True, help="model id served")
    ap.add_argument("--tag", required=True, help="label for output")
    ap.add_argument("--context", nargs="+", type=int, default=[4096, 32768])
    ap.add_argument("--tokens", type=int, default=64)
    ap.add_argument("--out-dir", default=os.path.expanduser("~/ai/artifacts/qwen38-bench"))

    ap.add_argument("--ssd-cache", action="store_true", help="run SSD KV-cache test")
    ap.add_argument("--omlx-bin", default=None)
    ap.add_argument("--model-dir", default=None)
    ap.add_argument("--port", type=int, default=8083)
    ap.add_argument("--memory-guard-gb", type=int, default=40)
    ap.add_argument("--omlx-base", default=None)
    ap.add_argument("--log-dir", default=os.path.expanduser("~/ai/artifacts/qwen38-bench/logs"))
    ap.add_argument("--timeout", type=float, default=300.0)
    args = ap.parse_args()

    results = run_ssd_cache(args) if args.ssd_cache else run_default(args)

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / f"{args.tag}.json"
    out_file.write_text(json.dumps(results, indent=2))
    print(f"\nWrote {out_file}")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
