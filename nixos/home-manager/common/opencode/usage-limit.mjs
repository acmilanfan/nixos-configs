// Wait out a subscription usage limit instead of failing the turn (idea from
// t3code's usage-limit recovery; Claude Code already does this on its own).
// opencode retries short rate limits itself (about 1.5 min in total, provider
// delays capped at 15 min) and fails the turn on a quota or usage limit. This
// retry hook turns a limit with a known reset time into one long retry that
// resumes the same turn. The reset may come from the body/message, the
// response's retry-after header, or opencode's retryAfterMs.
// OPENCODE_LIMIT_RESUME=0 disables it.

const DAY = 24 * 60 * 60 * 1000;
// Reset times are rounded; asking a little late avoids a second failure.
// (Overridable so the runtime test doesn't wait a minute.)
const MARGIN = Number(process.env.OPENCODE_LIMIT_RESUME_MARGIN_MS ?? 60 * 1000);
const LIMIT_TYPES = new Set(["provider.quota", "provider.rate-limit"]);
// Limits that no amount of waiting fixes.
const BILLING =
  /insufficient[-_\s]?(?:quota|balance)|billing|payment|credit balance|budget exceeded|package has expired|plan does not (?:yet )?include/i;

const UNIT_MS = { d: 86400000, h: 3600000, m: 60000, s: 1000 };
// Header resets are read from the HTTP response before the error reaches the
// retry hook. Older opencode versions drop retryAfterMs from that error.
const HEADER_TTL = 5 * 60 * 1000;
const headerResets = new Map();

function header(headers, name) {
  if (!headers) return undefined;
  return typeof headers.get === "function" ? headers.get(name) : headers[name];
}

/** Retry-after delay in ms from response headers, if the provider sent one. */
export function retryAfterFromHeaders(headers, now = Date.now()) {
  const rawMillis = header(headers, "retry-after-ms");
  const millis = Number(rawMillis);
  if (
    rawMillis !== undefined &&
    rawMillis !== null &&
    rawMillis !== "" &&
    Number.isFinite(millis) &&
    millis >= 0
  )
    return millis;
  const value = header(headers, "retry-after");
  if (!value) return undefined;
  const seconds = Number(value);
  if (Number.isFinite(seconds) && seconds >= 0) return seconds * 1000;
  const at = Date.parse(value);
  if (!Number.isNaN(at)) return Math.max(0, at - now);
  return undefined;
}

/** Remember a rate or quota response's reset for the retry hook in that session. */
export function noteResponse(event, now = Date.now()) {
  const status = event?.response?.status;
  if (status !== 429 && status !== 402) return;
  const delay = retryAfterFromHeaders(event.response.headers, now);
  if (delay === undefined) return;
  if (headerResets.size >= 1000) headerResets.delete(headerResets.keys().next().value);
  headerResets.set(event.sessionID, { at: now + delay, seen: now });
}

function parseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

// First value of any of `names`, searching nested objects (error bodies nest
// the interesting part under "error").
function field(value, names, depth = 0) {
  if (!value || typeof value !== "object" || depth > 4) return undefined;
  for (const name of names) if (value[name] !== undefined && value[name] !== null) return value[name];
  for (const nested of Object.values(value)) {
    const found = field(nested, names, depth + 1);
    if (found !== undefined) return found;
  }
  return undefined;
}

function toMillis(at) {
  if (typeof at === "number") return at > 1e12 ? at : at * 1000;
  if (typeof at === "string") {
    const t = Date.parse(at);
    return Number.isNaN(t) ? undefined : t;
  }
  return undefined;
}

/** When the limit behind `error` resets (epoch ms), if the error says so. */
export function resetAt(error, now = Date.now()) {
  const body = error?.response?.body ?? "";
  const json = parseJson(body);
  if (json) {
    const seconds = Number(field(json, ["resets_in_seconds", "reset_in_seconds", "retry_after_seconds"]));
    if (Number.isFinite(seconds) && seconds > 0) return now + seconds * 1000;
    const at = toMillis(field(json, ["resets_at", "reset_at", "resetsAt", "resetAt"]));
    if (at !== undefined) return at;
  }
  const text = `${error?.message ?? ""} ${body}`;
  // "try again in 2h 13m", "resets in 45 minutes", "available again in 3 hours"
  const relative = text.match(
    /(?:try again|resets?|available again)\s+in\s+((?:\d+\s*(?:days?|d|hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b[\s,]*(?:and\s+)?)+)/i,
  );
  if (relative) {
    let ms = 0;
    for (const [, n, unit] of relative[1].matchAll(/(\d+)\s*([a-z]+)/gi)) ms += Number(n) * UNIT_MS[unit[0].toLowerCase()];
    if (ms > 0) return now + ms;
  }
  // "resets at 2026-10-16T15:00:00Z" or "... 2026-10-16 15:00 UTC"
  const iso = text.match(/\b\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(?::\d{2})?(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2}|\s?UTC)?/);
  if (iso) {
    const t = Date.parse(iso[0].replace(/\s?UTC$/, "Z").replace(" ", "T"));
    if (!Number.isNaN(t)) return t;
  }
  // Providers often put the reset only in a retry-after header. OpenCode
  // surfaces it as retryAfterMs counted from the failure.
  const retryAfterMs = Number(error?.retryAfterMs);
  if (Number.isFinite(retryAfterMs) && retryAfterMs >= 0) return now + retryAfterMs;
  return undefined;
}

/**
 * Retry-hook decision: wait until the reset when the failure is a usage
 * limit with a known reset time. Returns the delay it set, if any.
 */
export function decide(event, now = Date.now()) {
  const error = event?.error;
  if (!error || !LIMIT_TYPES.has(error.type)) return undefined;
  if (BILLING.test(`${error.message ?? ""} ${error.response?.body ?? ""}`)) return undefined;
  let at = resetAt(error, now);
  const captured = headerResets.get(event.sessionID);
  if (captured) {
    headerResets.delete(event.sessionID);
    if (Math.abs(now - captured.seen) <= HEADER_TTL)
      at = at === undefined ? captured.at : Math.max(at, captured.at);
  }
  if (at === undefined) return undefined;
  const delay = Math.ceil(at - now + MARGIN);
  if (delay > DAY) return undefined;
  // opencode's own short retry already covers it
  if (event.decision?.retry && delay <= event.decision.delay) return undefined;
  // A quota is terminal to opencode, so a reset that just passed still needs
  // one short recheck instead of becoming an immediate failure. Rate limits
  // keep opencode's own shorter retry unless the reset is farther away.
  const wait = Math.max(MARGIN, delay);
  event.decision = { retry: true, delay: wait };
  return wait;
}

export default {
  id: "usage-limit",
  async setup(ctx) {
    if (process.env.OPENCODE_LIMIT_RESUME === "0") return;
    await ctx.session.hook("http.response", (event) => noteResponse(event));
    await ctx.session.hook("retry", (event) => {
      const delay = decide(event);
      if (delay !== undefined) {
        const at = new Date(Date.now() + delay).toISOString();
        console.error(`[usage-limit] ${event.sessionID}: ${event.error.type}, resuming at ${at}`);
      }
    });
  },
};
