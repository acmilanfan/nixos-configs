#!/usr/bin/env python3
"""RETRACTED - superseded by bench-llm. Its TTFT numbers are invalid.

The claim below that it "sends a fresh (non-SSD-cached) prefill" is false:
`build_prompt()` is fully deterministic, so repeat invocations at the same
size replay a byte-identical prompt and hit oMLX's SSD prefix cache. The
2026-08-19 report ran this probe three times (omlx-context-probe.json,
omlx-ceiling-probe.json, omlx-ceiling2.json) over overlapping sizes, so runs
2 and 3 were cache hits. That is why it reports 148k tokens prefilled in
42.6s (~3500 prompt tok/s, impossible on an M4 Pro).

It does read `usage.prompt_tokens` (line ~75), which is where the accurate
"actual tokens" column came from - but that count was never used to compute a
prefill rate, and the prompts overshot their targets by ~30%.

The REJECTED/OK ceiling column is still directionally useful: those rejections
came from oMLX's prefill memory-guard estimate, not real RAM.

Kept only so the previous report's provenance stays auditable.
See docs/superpowers/specs/2026-08-19-local-llm-prefill-design.md.

---

Original docstring follows.

Probe how large a context oMLX can serve on this machine.

For each target context size, sends a fresh (non-SSD-cached) prefill with
max_tokens=1 and reports success, TTFT, and peak phys_footprint. Steps up
until a request fails (context-length or OOM).

Usage: uvx --from openai python omlx-context-probe.py --base-url ... --model ...
"""
import argparse
import subprocess
import time
import json
from datetime import datetime, timezone

import openai


def build_prompt(n_tokens: int) -> str:
    word = "loremipsumdolorsitametconsectetur"
    per_token = 4
    chunk = word * 3
    reps = max(1, (n_tokens * per_token) // len(chunk))
    body = " ".join(chunk for _ in range(reps))
    return (
        "You are a careful assistant. Read the following reference text and "
        "answer the question precisely.\n\n---REFERENCE---\n" + body +
        "\n---END REFERENCE---\n\nQuestion: Summarize the theme in one sentence.\nAnswer:"
    )


def phys_footprint_peak_gb(pid):
    try:
        out = subprocess.run(["/usr/bin/footprint", "-p", str(pid)],
                             capture_output=True, text=True, timeout=30).stdout
        for line in out.splitlines():
            if line.strip().startswith("phys_footprint_peak:"):
                parts = line.split(":", 1)[1].strip().split()
                val = float(parts[0])
                unit = parts[1].lower() if len(parts) > 1 else "gb"
                gb = {"kb": 1e-6, "mb": 1e-3, "gb": 1.0}.get(unit, 1.0)
                return round(val * gb, 2)
    except Exception:
        pass
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--pid", type=int, default=None, help="omlx server pid")
    ap.add_argument("--sizes", nargs="+", type=int,
                    default=[32768, 65536, 98304, 131072, 196608, 262144])
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    client = openai.OpenAI(base_url=args.base_url, api_key="local")
    results = {"timestamp": datetime.now(timezone.utc).isoformat(),
               "model": args.model, "probes": []}

    for size in args.sizes:
        prompt = build_prompt(size)
        est = len(prompt) // 4
        rec = {"target": size, "prompt_approx_tokens": est}
        t0 = time.perf_counter()
        try:
            r = client.chat.completions.create(
                model=args.model, messages=[{"role": "user", "content": prompt}],
                max_tokens=1, temperature=0.0, stream=False, timeout=1800)
            dt = time.perf_counter() - t0
            rec["success"] = True
            rec["ttft_s"] = round(dt, 2)
            if r.usage:
                rec["prompt_tokens_actual"] = r.usage.prompt_tokens
        except openai.BadRequestError as e:
            rec["success"] = False
            rec["error"] = str(e)[:200]
            dt = time.perf_counter() - t0
        except Exception as e:
            rec["success"] = False
            rec["error"] = f"{type(e).__name__}: {str(e)[:200]}"
            dt = time.perf_counter() - t0
        rec["elapsed_s"] = round(time.perf_counter() - t0, 1)
        if args.pid:
            rec["peak_footprint_gb"] = phys_footprint_peak_gb(args.pid)
        print(json.dumps(rec))
        results["probes"].append(rec)
        if not rec["success"]:
            print(f"STOPPING at {size}: {rec['error']}")
            break

    if args.out:
        with open(args.out, "w") as f:
            json.dump(results, f, indent=2)
        print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
