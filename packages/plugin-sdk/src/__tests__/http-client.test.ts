/**
 * HttpClient 单元测试
 * 验证 Plugin SDK 的 HTTP 出站请求格式是否正确。
 * 这些请求会发往 Router 的 HTTP API。
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import { GatewayChannel } from "../GatewayChannel.js";
import { HttpClient } from "../http-client.js";

type MockFetch = ReturnType<typeof vi.fn>;

function createMockGlobalFetch(mockResponse: { ok: boolean; status: number; body?: unknown }) {
  const mockFetch = vi.fn(() =>
    Promise.resolve({
      ok: mockResponse.ok,
      status: mockResponse.status,
      statusText: mockResponse.status.toString(),
      headers: new Map([["content-type", "application/json"]]),
      json: () => Promise.resolve(mockResponse.body ?? {}),
    })
  );
  return mockFetch;
}

describe("HttpClient", () => {
  let originalFetch: typeof global.fetch;
  let mockFetch: MockFetch;
  let httpClient: HttpClient;

  const BASE_URL = "https://boson-tech.top";
  const TOKEN = "test-token-abc123";

  beforeEach(() => {
    originalFetch = global.fetch;
  });

  afterEach(() => {
    global.fetch = originalFetch;
    vi.restoreAllMocks();
  });

  // ─── reportCommandResult ─────────────────────────────────────────────────────

  describe("reportCommandResult", () => {
    it("POSTs to /api/callback/:requestId with correct body", async () => {
      mockFetch = createMockGlobalFetch({ ok: true, status: 200 });
      global.fetch = mockFetch as typeof global.fetch;

      httpClient = new HttpClient({ baseUrl: BASE_URL, token: TOKEN });

      await httpClient.reportCommandResult({
        requestId: "r-12345",
        success: true,
        result: { output: "done" },
        durationMs: 150,
      });

      expect(mockFetch).toHaveBeenCalledTimes(1);
      const [url, options] = mockFetch.mock.calls[0] as [string, RequestInit];

      expect(url).toBe("https://boson-tech.top/api/callback/r-12345");
      expect(options.method).toBe("POST");

      const body = JSON.parse(options.body as string);
      expect(body.success).toBe(true);
      expect(body.result).toEqual({ output: "done" });
      expect(body.durationMs).toBe(150);
    });

    it("includes X-Plugin-Token header", async () => {
      mockFetch = createMockGlobalFetch({ ok: true, status: 200 });
      global.fetch = mockFetch as typeof global.fetch;

      httpClient = new HttpClient({ baseUrl: BASE_URL, token: TOKEN });
      await httpClient.reportCommandResult({
        requestId: "r-1",
        success: false,
        durationMs: 0,
      });

      const headers = mockFetch.mock.calls[0][1].headers as Record<string, string>;
      expect(headers["X-Plugin-Token"]).toBe(TOKEN);
      expect(headers["Content-Type"]).toBe("application/json");
    });

    it("throws on non-ok response", async () => {
      mockFetch = createMockGlobalFetch({ ok: false, status: 401 });
      global.fetch = mockFetch as typeof global.fetch;

      httpClient = new HttpClient({ baseUrl: BASE_URL, token: TOKEN });

      await expect(
        httpClient.reportCommandResult({ requestId: "r-1", success: true, durationMs: 0 })
      ).rejects.toThrow("HTTP POST https://boson-tech.top/api/callback/r-1 returned 401");
    });

    it("throws on network failure", async () => {
      mockFetch = vi.fn(() => Promise.reject(new Error("ECONNREFUSED")));
      global.fetch = mockFetch as typeof global.fetch;

      httpClient = new HttpClient({ baseUrl: BASE_URL, token: TOKEN });

      await expect(
        httpClient.reportCommandResult({ requestId: "r-1", success: true, durationMs: 0 })
      ).rejects.toThrow("HTTP POST failed: ECONNREFUSED");
    });

    it("strips trailing slash from baseUrl", async () => {
      mockFetch = createMockGlobalFetch({ ok: true, status: 200 });
      global.fetch = mockFetch as typeof global.fetch;

      httpClient = new HttpClient({ baseUrl: "https://boson-tech.top///", token: TOKEN });
      await httpClient.reportCommandResult({ requestId: "r-1", success: true, durationMs: 0 });

      const [url] = mockFetch.mock.calls[0] as [string, RequestInit];
      expect(url).toBe("https://boson-tech.top/api/callback/r-1");
    });
  });

  // ─── pushEvent ─────────────────────────────────────────────────────────────

  describe("pushEvent", () => {
    it("POSTs to /api/plugin/event with correct body", async () => {
      mockFetch = createMockGlobalFetch({ ok: true, status: 202 });
      global.fetch = mockFetch as typeof global.fetch;

      httpClient = new HttpClient({ baseUrl: BASE_URL, token: TOKEN });

      await httpClient.pushEvent({
        backendId: "backend-abc",
        event: "agent_status_changed",
        data: { status: "busy" },
      });

      expect(mockFetch).toHaveBeenCalledTimes(1);
      const [url, options] = mockFetch.mock.calls[0] as [string, RequestInit];

      expect(url).toBe("https://boson-tech.top/api/plugin/event");
      expect(options.method).toBe("POST");

      const body = JSON.parse(options.body as string);
      expect(body.backend_id).toBe("backend-abc");
      expect(body.event).toBe("agent_status_changed");
      expect(body.data).toEqual({ status: "busy" });
    });

    it("includes X-Plugin-Token header", async () => {
      mockFetch = createMockGlobalFetch({ ok: true, status: 202 });
      global.fetch = mockFetch as typeof global.fetch;

      httpClient = new HttpClient({ baseUrl: BASE_URL, token: TOKEN });
      await httpClient.pushEvent({ backendId: "b-1", event: "test", data: {} });

      const headers = mockFetch.mock.calls[0][1].headers as Record<string, string>;
      expect(headers["X-Plugin-Token"]).toBe(TOKEN);
    });

    it("throws on non-ok response", async () => {
      mockFetch = createMockGlobalFetch({ ok: false, status: 404 });
      global.fetch = mockFetch as typeof global.fetch;

      httpClient = new HttpClient({ baseUrl: BASE_URL, token: TOKEN });

      await expect(
        httpClient.pushEvent({ backendId: "b-1", event: "test", data: {} })
      ).rejects.toThrow("HTTP POST https://boson-tech.top/api/plugin/event returned 404");
    });
  });

  // ─── ai.chat ─────────────────────────────────────────────────────────────

  describe("ai.chat", () => {
    it("POSTs backend AI chat requests with backend identity headers", async () => {
      mockFetch = createMockGlobalFetch({
        ok: true,
        status: 200,
        body: {
          id: "ai_123",
          model_profile_id: "default",
          message: { role: "assistant", content: "hello from router" },
          usage: { prompt_tokens: 3, completion_tokens: 4 },
          billing: { charged_cents: 0, usage_event_id: "usage_1" },
        },
      });
      global.fetch = mockFetch as typeof global.fetch;

      httpClient = new HttpClient({ baseUrl: `${BASE_URL}/`, token: TOKEN });

      const response = await httpClient.chat({
        backendId: "backend-abc",
        accountId: "acct-123",
        modelProfileId: "default",
        agentProfileId: "profile-openclaw",
        messages: [{ role: "user", content: "hello" }],
      });

      expect(response.message.content).toBe("hello from router");
      expect(response.billing.charged_cents).toBe(0);
      expect(mockFetch).toHaveBeenCalledTimes(1);

      const [url, options] = mockFetch.mock.calls[0] as [string, RequestInit];
      expect(url).toBe("https://boson-tech.top/api/v2/backend/ai/chat");
      expect(options.method).toBe("POST");

      const headers = options.headers as Record<string, string>;
      expect(headers["Content-Type"]).toBe("application/json");
      expect(headers["X-Plugin-Token"]).toBe(TOKEN);
      expect(headers["X-Boson-Backend-Id"]).toBe("backend-abc");

      const body = JSON.parse(options.body as string);
      expect(body).toEqual({
        account_id: "acct-123",
        model_profile_id: "default",
        agent_profile_id: "profile-openclaw",
        messages: [{ role: "user", content: "hello" }],
      });
    });

    it("surfaces Router AI errors with status and code", async () => {
      mockFetch = createMockGlobalFetch({
        ok: false,
        status: 402,
        body: { error: { code: "PAYMENT_REQUIRED", message: "Insufficient wallet balance" } },
      });
      global.fetch = mockFetch as typeof global.fetch;

      httpClient = new HttpClient({ baseUrl: BASE_URL, token: TOKEN });

      await expect(
        httpClient.chat({
          backendId: "backend-abc",
          accountId: "acct-123",
          messages: [{ role: "user", content: "hello" }],
        })
      ).rejects.toMatchObject({
        statusCode: 402,
        code: "PAYMENT_REQUIRED",
      });
    });
  });

  describe("GatewayChannel.ai", () => {
    it("exposes Router AI chat through the channel facade", async () => {
      mockFetch = createMockGlobalFetch({
        ok: true,
        status: 200,
        body: {
          id: "ai_channel",
          model_profile_id: "default",
          message: { role: "assistant", content: "facade response" },
          usage: {},
          billing: { charged_cents: 0, usage_event_id: null },
        },
      });
      global.fetch = mockFetch as typeof global.fetch;

      const channel = new GatewayChannel({
        baseUrl: BASE_URL,
        agentId: "agent-1",
        token: TOKEN,
        tenantId: "tenant-1",
      });

      const response = await channel.ai.chat({
        backendId: "backend-abc",
        accountId: "acct-123",
        messages: [{ role: "user", content: "hello" }],
      });

      expect(response.message.content).toBe("facade response");
      const headers = mockFetch.mock.calls[0][1].headers as Record<string, string>;
      expect(headers["X-Boson-Backend-Id"]).toBe("backend-abc");
    });
  });
});
