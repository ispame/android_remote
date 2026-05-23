/**
 * Plugin ↔ Router 接口配套集成测试
 *
 * 验证 Plugin SDK（WsClient + HttpClient）与 Router HTTP API 的接口格式是否匹配。
 * Mock Router 是一个同时监听 HTTP + WebSocket 的真实服务器。
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import http from "http";
import WebSocket, { WebSocketServer } from "ws";
import type { IncomingMessage } from "http";
import type { Duplex } from "stream";

import type { HttpClient } from "../http-client.js";
import type { WsClient } from "../WsClient.js";
import type { Logger } from "../logger.js";

// ─── Mock Router（HTTP + WebSocket 同一端口）───────────────────────────────────

interface MockRouterOptions {
  token?: string;
  tenantId?: string;
  /** If provided, WS upgrade path will be handled here */
  wsPath?: string;
}

function createMockRouter(options: MockRouterOptions = {}) {
  const { token = "test-token", tenantId = "tenant-1" } = options;

  const requestLog: Array<{ method: string; path: string; body: unknown }> = [];

  // HTTP server that also handles WS upgrades
  const httpServer = http.createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on("data", (c: Buffer) => chunks.push(c));
    req.on("end", () => {
      let body: unknown = {};
      const raw = Buffer.concat(chunks).toString("utf-8");
      if (raw) {
        try { body = JSON.parse(raw); } catch { /* ignore */ }
      }
      requestLog.push({ method: req.method!, path: req.url!, body });

      // CORS preflight
      if (req.method === "OPTIONS") {
        res.writeHead(204, {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, X-Plugin-Token",
        });
        res.end();
        return;
      }

      // POST /api/ws/connect
      if (req.method === "POST" && req.url === "/api/ws/connect") {
        const b = body as Record<string, unknown>;
        if (!b.agent_id) {
          res.writeHead(400, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ code: 400, message: "agent_id required" }));
          return;
        }
        if (!b.token || b.token !== token) {
          res.writeHead(401, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ code: 401, message: "invalid token" }));
          return;
        }
        // Router does NOT validate tenant_id currently (known gap)
        const host = req.headers["host"] ?? "localhost:0";
        const endpoint = `ws://${host}/ws/plugin/test123`;
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({
          code: 0,
          data: {
            endpoint,
            ping_interval_ms: 25000,
            reconnect_interval_ms: 5000,
            reconnect_nonce_ms: 30000,
            reconnect_max: -1,
          },
        }));
        return;
      }

      // POST /api/callback/:requestId
      const callbackMatch = req.url?.match(/^\/api\/callback\/(.+)$/);
      if (req.method === "POST" && callbackMatch) {
        const b = body as Record<string, unknown>;
        if (typeof b.success !== "boolean") {
          res.writeHead(400, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "INVALID_REQUEST", message: "success required" }));
          return;
        }
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ acknowledged: true }));
        return;
      }

      // POST /api/plugin/event
      if (req.method === "POST" && req.url === "/api/plugin/event") {
        const b = body as Record<string, unknown>;
        if (!b.backend_id || !b.event) {
          res.writeHead(400, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "INVALID_REQUEST" }));
          return;
        }
        res.writeHead(202, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ receivedAt: new Date().toISOString(), delivered: 1 }));
        return;
      }

      // GET /health
      if (req.method === "GET" && req.url === "/health") {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ status: "ok" }));
        return;
      }

      res.writeHead(404);
      res.end();
    });
  });

  // WebSocket server on the same HTTP server (for real WS upgrade)
  const wss = new WebSocketServer({ noServer: true });

  // Track registered backends
  const registeredClients = new Map<string, WebSocket>();

  wss.on("connection", (ws: WebSocket, req: IncomingMessage) => {
    const url = new URL(req.url ?? "/", `http://${req.headers.host}`);
    const pathSegment = url.pathname; // e.g. /ws/plugin/test123

    let registeredBackendId: string | null = null;

    ws.on("message", (data: WebSocket.RawData) => {
      let raw: string;
      if (typeof data === "string") raw = data;
      else raw = data.toString("utf-8");

      let frame: Record<string, unknown>;
      try { frame = JSON.parse(raw); } catch { return; }

      if (frame.type === "backend_register") {
        const backendId = (frame.backend_id as string) || `backend-${Date.now()}`;
        registeredBackendId = backendId;
        registeredClients.set(backendId, ws);

        ws.send(JSON.stringify({
          type: "backend_registered",
          backend_id: backendId,
          backend_label: frame.backend_label ?? "TestPlugin",
          success: true,
        }));
        return;
      }

      // Handle other frame types in mock if needed
      ws.on("error", () => {});
    });

    ws.on("close", () => {
      if (registeredBackendId) registeredClients.delete(registeredBackendId);
    });
  });

  // Handle HTTP upgrade requests for WebSocket
  httpServer.on("upgrade", (req: IncomingMessage, socket: Duplex, head: Buffer) => {
    const url = new URL(req.url ?? "/", `http://${req.headers.host}`);
    if (url.pathname.startsWith("/ws/")) {
      wss.handleUpgrade(req, socket, head, (ws) => {
        wss.emit("connection", ws, req);
      });
    } else {
      socket.destroy();
    }
  });

  return { httpServer, wss, requestLog, registeredClients };
}

// ─── Null logger ───────────────────────────────────────────────────────────────

const nullLogger: Logger = {
  debug: () => {},
  info: () => {},
  warn: () => {},
  error: console.error,
};

// ─── Tests ────────────────────────────────────────────────────────────────────

describe("Plugin SDK ↔ Router 接口配套测试", () => {

  describe("HttpClient — Plugin HTTP 出站", () => {
    let router: ReturnType<typeof createMockRouter>;
    let port: number;
    let HttpClient: typeof import("../http-client.js").HttpClient;

    beforeEach(async () => {
      router = createMockRouter({ token: "router-accepts-this-token" });
      await new Promise<void>((resolve) => router.httpServer.listen(0, "127.0.0.1", resolve));
      port = (router.httpServer.address() as { port: number }).port;

      const mod = await import("../http-client.js");
      HttpClient = mod.HttpClient;
    });

    afterEach(() => {
      router.httpServer.close();
    });

    it("reportCommandResult → POST /api/callback/:id，格式正确", async () => {
      const client = new HttpClient({ baseUrl: `http://127.0.0.1:${port}`, token: "router-accepts-this-token" });

      await client.reportCommandResult({
        requestId: "r-abc123",
        success: true,
        result: { screenshotUrl: "http://cdn.example.com/img.png" },
        durationMs: 234,
      });

      expect(router.requestLog).toHaveLength(1);
      const req = router.requestLog[0];
      expect(req.method).toBe("POST");
      expect(req.path).toBe("/api/callback/r-abc123");
      const body = req.body as Record<string, unknown>;
      expect(body.success).toBe(true);
      expect(body.result).toEqual({ screenshotUrl: "http://cdn.example.com/img.png" });
      expect(body.durationMs).toBe(234);
    });

    it("reportCommandResult（失败）+ X-Plugin-Token header", async () => {
      const client = new HttpClient({ baseUrl: `http://127.0.0.1:${port}`, token: "router-accepts-this-token" });

      await client.reportCommandResult({
        requestId: "r-fail-001",
        success: false,
        durationMs: 50,
      });

      expect(router.requestLog).toHaveLength(1);
      // X-Plugin-Token 验证：mock Router 不验证此 header（符合真实 Router 行为），
      // 此处只验证请求格式正确（success=false），header 由 http-client.test.ts 单元测试覆盖
      const body = router.requestLog[0].body as Record<string, unknown>;
      expect(body.success).toBe(false);
    });

    it("pushEvent → POST /api/plugin/event，backend_id + event + data 正确", async () => {
      const client = new HttpClient({ baseUrl: `http://127.0.0.1:${port}`, token: "router-accepts-this-token" });

      await client.pushEvent({
        backendId: "backend-xyz",
        event: "collision_detected",
        data: { x: 100, y: 200, severity: "low" },
      });

      expect(router.requestLog).toHaveLength(1);
      const req = router.requestLog[0];
      expect(req.method).toBe("POST");
      expect(req.path).toBe("/api/plugin/event");
      const body = req.body as Record<string, unknown>;
      expect(body.backend_id).toBe("backend-xyz");
      expect(body.event).toBe("collision_detected");
      expect(body.data).toEqual({ x: 100, y: 200, severity: "low" });
    });
  });

  describe("WsClient — Plugin WS 出站（连接到 Router）", () => {
    let router: ReturnType<typeof createMockRouter>;
    let port: number;
    let WsClient: typeof import("../WsClient.js").WsClient;

    beforeEach(async () => {
      router = createMockRouter({ token: "valid-token-abc" });
      await new Promise<void>((resolve) => router.httpServer.listen(0, "127.0.0.1", resolve));
      port = (router.httpServer.address() as { port: number }).port;

      const mod = await import("../WsClient.js");
      WsClient = mod.WsClient;
    });

    afterEach(() => {
      router.httpServer.close();
    });

    it("POST /api/ws/connect → WS upgrade → backend_register 帧 → backend_registered 响应", async () => {
      let backendId: string | null = null;
      let readyCalled = false;
      const wsConnectCalls: unknown[] = [];

      const wsClient = new WsClient(
        {
          baseUrl: `http://127.0.0.1:${port}`,
          agentId: "test-agent",
          token: "valid-token-abc",
          tenantId: "tenant-1",
          label: "TestPlugin",
          log: nullLogger,
        },
        {
          onReady: (id) => { backendId = id; readyCalled = true; },
          onMessage: () => {},
          onPairRequest: () => {},
          onPairsList: () => {},
          onError: () => {},
          onClose: () => {},
          onWsError: () => {},
          onRouterPong: () => {},
        }
      );

      const ok = await wsClient.start();
      expect(ok).toBe(true);

      // Wait for async WS open + backend_register
      await new Promise<void>((resolve) => setTimeout(resolve, 200));

      expect(readyCalled).toBe(true);
      expect(backendId).toBeTruthy();

      // Verify: /api/ws/connect was called with correct fields
      const wsConnectReq = router.requestLog.find((r) => r.path === "/api/ws/connect");
      expect(wsConnectReq).toBeDefined();
      const connectBody = wsConnectReq!.body as Record<string, unknown>;
      expect(connectBody.agent_id).toBe("test-agent");
      expect(connectBody.token).toBe("valid-token-abc");
      expect(connectBody.tenant_id).toBe("tenant-1");

      // Verify: WS was established and backend_register frame was sent
      expect(router.registeredClients.size).toBeGreaterThanOrEqual(1);

      wsClient.stop();
    });

    it("token 无效 → /api/ws/connect 返回 401 → start() 返回 false", async () => {
      const badClient = new WsClient(
        {
          baseUrl: `http://127.0.0.1:${port}`,
          agentId: "test-agent",
          token: "WRONG-TOKEN",
          tenantId: "tenant-1",
          label: "TestPlugin",
          log: nullLogger,
        },
        {
          onReady: () => {},
          onMessage: () => {},
          onPairRequest: () => {},
          onPairsList: () => {},
          onError: () => {},
          onClose: () => {},
          onWsError: () => {},
          onRouterPong: () => {},
        }
      );

      const ok = await badClient.start();
      expect(ok).toBe(false);
    });
  });

  describe("Router HTTP API 边界验证", () => {
    let router: ReturnType<typeof createMockRouter>;
    let port: number;

    beforeEach(async () => {
      router = createMockRouter({ token: "test-token" });
      await new Promise<void>((resolve) => router.httpServer.listen(0, "127.0.0.1", resolve));
      port = (router.httpServer.address() as { port: number }).port;
    });

    afterEach(() => {
      router.httpServer.close();
    });

    it("POST /api/ws/connect 缺少 agent_id → 400", async () => {
      const res = await fetch(`http://127.0.0.1:${port}/api/ws/connect`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token: "test-token" }),
      });
      expect(res.status).toBe(400);
      const body = await res.json();
      expect(body.code).toBe(400);
    });

    it("POST /api/ws/connect 缺少 token → 401", async () => {
      const res = await fetch(`http://127.0.0.1:${port}/api/ws/connect`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ agent_id: "test-agent" }),
      });
      expect(res.status).toBe(401);
    });

    it("POST /api/ws/connect token 错误 → 401", async () => {
      const res = await fetch(`http://127.0.0.1:${port}/api/ws/connect`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ agent_id: "test-agent", token: "bad-token" }),
      });
      expect(res.status).toBe(401);
    });

    it("POST /api/ws/connect 正确 → 200 + endpoint + ping_interval_ms", async () => {
      const res = await fetch(`http://127.0.0.1:${port}/api/ws/connect`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ agent_id: "test-agent", token: "test-token", tenant_id: "tenant-1" }),
      });
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.code).toBe(0);
      expect(body.data.endpoint).toMatch(/^ws:\/\/.+/);
      expect(body.data.ping_interval_ms).toBe(25000);
      expect(body.data.reconnect_interval_ms).toBe(5000);
      expect(body.data.reconnect_nonce_ms).toBe(30000);
      expect(body.data.reconnect_max).toBe(-1);
    });

    it("POST /api/callback/:id 缺少 success → 400", async () => {
      const res = await fetch(`http://127.0.0.1:${port}/api/callback/r-123`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ result: {} }),
      });
      expect(res.status).toBe(400);
    });

    it("POST /api/plugin/event 缺少 backend_id → 400", async () => {
      const res = await fetch(`http://127.0.0.1:${port}/api/plugin/event`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ event: "test" }),
      });
      expect(res.status).toBe(400);
    });

    it("GET /health → 200 + status:ok", async () => {
      const res = await fetch(`http://127.0.0.1:${port}/health`);
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.status).toBe("ok");
    });
  });
});
