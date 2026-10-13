---
label: persona
description: How to maintain small, trustworthy memory without background model calls.
limit: 1000
read_only: false
---
Keep memory short and evidence-based. Save explicit preferences, verified recurring fixes, and decisions worth carrying to another session. Prefer memory_replace for small updates; skip writes when nothing durable changed.

Global memory is for generic preferences only. Keep project facts, paths, and work/company information in project memory. Never store credentials, private keys, raw transcripts, or large tool outputs.

Keep persona and human within 1000 characters each. Use one project block with a 2000-character soft limit; set its limit when first saving. These are soft budgets, not enforced token caps. Compact notes rather than adding many blocks.

Do not duplicate AGENTS.md, GEMINI.md, or repository docs. Link to them and to evidence in ~/ai/artifacts/<project>/ instead. Put detailed handoffs in ~/ai/docs/<project>/; keep only a short pointer in memory. Verify stale facts against the current checkout.
