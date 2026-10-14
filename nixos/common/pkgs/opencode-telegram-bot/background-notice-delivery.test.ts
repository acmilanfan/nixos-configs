import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Bot, Context } from "grammy";
import type { Event, PermissionRequest } from "@opencode-ai/sdk/v2";
import { createBackgroundNoticeDelivery } from "../../../src/bot/events/background-notice-delivery.js";
import { TelegramEventDelivery } from "../../../src/bot/events/telegram-event-delivery.js";
import type { BackgroundSessionNotification } from "../../../src/app/managers/background-session-manager.js";
import { createEventSubscriptionService } from "../../../src/bot/services/event-subscription-service.js";
import { createTestAppContainer } from "../../helpers/app-container.js";

const mocked = vi.hoisted(() => ({ list: vi.fn(), subscribe: vi.fn(), stop: vi.fn() }));
vi.mock("../../../src/opencode/events.js", () => ({
  subscribeToEvents: mocked.subscribe,
  stopEventListening: mocked.stop,
}));
vi.mock("../../../src/opencode/client.js", () => ({
  opencodeClient: { permission: { list: mocked.list } },
}));
vi.mock("../../../src/utils/logger.js", () => ({
  logger: { debug: vi.fn(), info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

const permission: BackgroundSessionNotification = {
  kind: "permission_asked",
  sessionId: "session-background",
  sessionTitle: "Branch review",
  requestId: "permission-1",
};

function pending(id = "permission-1", sessionID = "session-background"): PermissionRequest {
  return { id, sessionID, permission: "shell", patterns: ["git status"], always: [], metadata: {} };
}

function setup() {
  const messages: string[] = [];
  const api = {
    sendMessage: vi.fn(async (_chatId: number, text: string) => {
      messages.push(text);
      return { message_id: messages.length };
    }),
  } as unknown as Bot<Context>["api"];
  let connected = true;
  let active = true;
  const notify = createBackgroundNoticeDelivery(
    { getDestination: () => (connected ? { api, chatId: 123 } : null) },
    new TelegramEventDelivery(),
    "/projects/review",
    () => active,
  );
  return {
    api,
    notify,
    messages,
    disconnect: () => { connected = false; },
    invalidateSubscription: () => { active = false; },
  };
}

describe("background permission notice grace period", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    mocked.list.mockResolvedValue({ data: [pending()] });
    mocked.subscribe.mockResolvedValue(undefined);
  });
  afterEach(() => vi.useRealTimers());

  it("suppresses a request approved by another client during the grace period", async () => {
    const { notify, messages } = setup();
    const delivery = notify(permission);
    await vi.advanceTimersByTimeAsync(100);
    mocked.list.mockResolvedValue({ data: [] });
    await vi.runAllTimersAsync();
    await delivery;
    expect(messages).toEqual([]);
  });

  it("delays a genuinely pending request, then sends one alert in its directory", async () => {
    const { notify, messages } = setup();
    const delivery = notify(permission);
    await vi.advanceTimersByTimeAsync(100);
    expect(messages).toEqual([]);
    await vi.runAllTimersAsync();
    await delivery;
    expect(messages).toHaveLength(1);
    expect(messages[0]).toContain("Branch review");
    expect(mocked.list).toHaveBeenCalledWith({ directory: "/projects/review" });
  });

  it("does not mistake another request or another session for the pending request", async () => {
    mocked.list.mockResolvedValue({
      data: [pending("permission-other"), pending("permission-1", "session-other")],
    });
    const { notify, messages } = setup();
    const delivery = notify(permission);
    await vi.runAllTimersAsync();
    await delivery;
    expect(messages).toEqual([]);
  });

  it.each(["question_asked", "assistant_response"] as const)(
    "keeps %s notifications immediate",
    async (kind) => {
      const { notify, messages } = setup();
      await notify({ ...permission, kind });
      expect(messages).toHaveLength(1);
      expect(mocked.list).not.toHaveBeenCalled();
    },
  );

  it.each(["returned", "thrown", "missing-data"])(
    "keeps the alert when the pending-request lookup fails (%s)",
    async (failure) => {
      if (failure === "thrown") {
        mocked.list.mockRejectedValue(new Error("offline"));
      } else {
        mocked.list.mockResolvedValue(failure === "returned" ? { error: { message: "offline" } } : {});
      }
      const { notify, messages } = setup();
      const delivery = notify(permission);
      await vi.runAllTimersAsync();
      await delivery;
      expect(messages).toHaveLength(1);
    },
  );

  it("does not send a delayed alert after the Telegram destination is disconnected", async () => {
    const { notify, messages, disconnect } = setup();
    const delivery = notify(permission);
    disconnect();
    await vi.runAllTimersAsync();
    await delivery;
    expect(messages).toEqual([]);
  });

  it("still alerts when the server lookup never responds", async () => {
    mocked.list.mockReturnValue(new Promise(() => {}));
    const { notify, messages } = setup();
    const delivery = notify(permission);
    await vi.advanceTimersByTimeAsync(10000);
    expect(messages).toHaveLength(1);
    await delivery;
  });

  it("cancels an old subscription's delayed alert while Telegram stays connected", async () => {
    const { notify, messages, invalidateSubscription } = setup();
    const delivery = notify(permission);
    invalidateSubscription();
    await vi.runAllTimersAsync();
    await delivery;
    expect(messages).toEqual([]);
    expect(mocked.list).not.toHaveBeenCalled();
  });

  it("cancels an old subscription's alert while its pending-request lookup is in flight", async () => {
    let finishLookup!: (value: { data: PermissionRequest[] }) => void;
    mocked.list.mockReturnValue(new Promise((resolve) => { finishLookup = resolve; }));
    const { notify, messages, invalidateSubscription } = setup();
    const delivery = notify(permission);
    await vi.advanceTimersByTimeAsync(1500);
    invalidateSubscription();
    finishLookup({ data: [pending()] });
    await delivery;
    expect(messages).toEqual([]);
  });

  it("checks simultaneous requests independently", async () => {
    mocked.list.mockResolvedValue({ data: [pending("permission-2")] });
    const { notify, messages } = setup();
    const deliveries = Promise.all([
      notify(permission),
      notify({ ...permission, requestId: "permission-2" }),
    ]);
    await vi.runAllTimersAsync();
    await deliveries;
    expect(messages).toHaveLength(1);
  });

  it.each([
    { action: "same-directory refresh", expected: 1 },
    { action: "project switch", expected: 0 },
    { action: "cleanup", expected: 0 },
  ])("delivers the correct pending alerts after $action", async ({ action, expected }) => {
    const deps = createTestAppContainer();
    const service = createEventSubscriptionService(deps);
    const { api, messages } = setup();
    service.setTelegramContext({ api } as Bot<Context>, 123);
    await service.ensureEventSubscription("/projects/review");
    deps.backgroundSessionTracker.processEvent({
      type: "permission.asked",
      properties: pending(),
    } as Event, null);
    await vi.advanceTimersByTimeAsync(0);
    if (action === "cleanup") {
      service.cleanup("test_reset");
    } else {
      await service.ensureEventSubscription(
        action === "project switch" ? "/projects/other" : "/projects/review",
      );
    }
    await vi.runAllTimersAsync();
    expect(messages).toHaveLength(expected);
    service.cleanup("test_finished");
  });
});
