import assert from "node:assert/strict";
import test from "node:test";

const plugin = () => import("../usage-limit.mjs");

const NOW = Date.parse("2026-10-16T12:00:00Z");
const MIN = 60 * 1000;

function failure(type, { message = "limit", body, decision = { retry: false } } = {}) {
  return {
    sessionID: "ses_one",
    attempt: 2,
    error: { type, message, status: 429, ...(body === undefined ? {} : { response: { body } }) },
    decision,
  };
}

test("a ChatGPT usage limit waits until its reset and retries the same turn", async () => {
  const { decide } = await plugin();
  const event = failure("provider.quota", {
    body: JSON.stringify({ error: { type: "usage_limit_reached", resets_in_seconds: 2 * 3600 } }),
  });
  assert.equal(decide(event, NOW), 2 * 3600 * 1000 + MIN);
  assert.deepEqual(event.decision, { retry: true, delay: 2 * 3600 * 1000 + MIN });
});

test("reset times come from epoch, ISO and relative text", async () => {
  const { resetAt } = await plugin();
  const epoch = NOW / 1000 + 600;
  assert.equal(resetAt({ response: { body: JSON.stringify({ resets_at: epoch }) } }, NOW), NOW + 600 * 1000);
  assert.equal(resetAt({ response: { body: JSON.stringify({ error: { reset_at: "2026-10-16T15:00:00Z" } }) } }, NOW),
    Date.parse("2026-10-16T15:00:00Z"));
  assert.equal(resetAt({ message: "Usage limit reached, try again in 2h 13m" }, NOW), NOW + (2 * 60 + 13) * MIN);
  assert.equal(resetAt({ message: "limit resets in 45 minutes" }, NOW), NOW + 45 * MIN);
  assert.equal(resetAt({ message: "spend limit reached (daily; resets 2026-10-17 00:00 UTC)" }, NOW),
    Date.parse("2026-10-17T00:00:00Z"));
  assert.equal(resetAt({ message: "quota exceeded" }, NOW), undefined);
});

test("billing errors, unknown resets, other errors and far-away resets keep opencode's decision", async () => {
  const { decide } = await plugin();
  const cases = [
    failure("provider.quota", { message: "insufficient_quota: add credits", body: JSON.stringify({ resets_in_seconds: 60 }) }),
    failure("provider.quota", { message: "quota exceeded" }),
    failure("provider.auth", { message: "try again in 5 minutes" }),
    failure("provider.quota", { body: JSON.stringify({ resets_in_seconds: 3 * 24 * 3600 }) }),
  ];
  for (const event of cases) {
    assert.equal(decide(event, NOW), undefined);
    assert.deepEqual(event.decision, { retry: false });
  }
});

test("a short rate limit opencode already retries sooner is left alone", async () => {
  const { decide } = await plugin();
  const event = failure("provider.rate-limit", {
    message: "rate limit, try again in 30 seconds",
    decision: { retry: true, delay: 10 * MIN },
  });
  assert.equal(decide(event, NOW), undefined);
  assert.deepEqual(event.decision, { retry: true, delay: 10 * MIN });
});

test("the plugin registers a retry hook unless disabled", async () => {
  const { default: definition } = await plugin();
  const hooks = [];
  const ctx = { session: { hook: async (name, fn) => hooks.push([name, fn]) } };
  await definition.setup(ctx);
  assert.deepEqual(hooks.map(([name]) => name), ["retry"]);
  process.env.OPENCODE_LIMIT_RESUME = "0";
  try {
    await definition.setup(ctx);
    assert.equal(hooks.length, 1);
  } finally {
    delete process.env.OPENCODE_LIMIT_RESUME;
  }
});
