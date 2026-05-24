/**
 * WebSocket client that manages the Plugin's outgoing WS connection to Router.
 *
 * Responsibilities:
 * - Fetch WS endpoint via HTTP POST /api/ws/connect
 * - Establish and maintain the WebSocket connection
 * - Send the backend_register frame after connection
 * - Handle incoming frames (parse + dispatch)
 * - Handle pong detection for heartbeat
 * - Trigger reconnect on unexpected close/error
 *
 * Does NOT handle reconnection scheduling — that is delegated to ReconnectManager.
 */

import WebSocket, { type RawData } from "ws";
import type { Logger } from "./logger.js";
import { parseFrame, FrameParseError } from "./protocol/parse.js";
import { serializeFrame } from "./protocol/serialize.js";
import type {
  IncomingFrame,
  RegisterFrame,
  RegisteredFrame,
  RegisterErrorFrame,
  MessageFrame,
  PairRequestFrame,
  PairsListFrame,
  PairResponseFrame,
  ErrorFrame,
  WsConnectResponse,
  MessageAckFrame,
} from "./protocol/types.js";

export interface WsClientConfig {
  /** Base URL of Router (e.g., https://boson-tech.top). */
  baseUrl: string;
  /** Agent ID for this plugin. */
  agentId: string;
  /** Plugin token for authentication. */
  token: string;
  /** Tenant ID. */
  tenantId: string;
  /** Plugin label (sent in backend_register frame). */
  label?: string;
  /** Custom WebSocket agent (for proxy, TLS, etc.). */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  agent?: any;
  /** Logger instance. */
  log: Logger;
}

export interface WsClientDeps {
  /** Called when connection is established and registered. */
  onReady: (backendId: string) => void;
  /** Called when a message frame is received. */
  onMessage: (frame: MessageFrame) => void;
  /** Called when a pair_request is received. */
  onPairRequest: (frame: PairRequestFrame) => void;
  /** Called when the paired device list is received. */
  onPairsList: (frame: PairsListFrame) => void;
  /** Called when an error frame is received. */
  onError: (frame: ErrorFrame) => void;
  /** Called when WebSocket is closed unexpectedly. */
  onClose: () => void;
  /** Called when WebSocket error occurs. */
  onWsError: (err: Error) => void;
  /** Called when a router pong is received (for heartbeat). */
  onRouterPong: () => void;
}

const WS_CONNECT_PATH = "/api/ws/connect";

/**
 * WebSocket client for Plugin-Router communication.
 */
export class WsClient {
  private config: WsClientConfig;
  private deps: WsClientDeps;
  private ws: WebSocket | null = null;
  private registeredBackendId: string | null = null;
  private stopped = false;
  private receivedMessageKeys = new Set<string>();
  private receivedMessageKeyOrder: string[] = [];

  // WS config obtained from /api/ws/connect response
  private wsEndpoint: string | null = null;
  private pingIntervalMs: number | null = null;
  private reconnectIntervalMs: number | null = null;
  private reconnectNonceMs: number | null = null;
  private reconnectMax: number | null = null;

  constructor(config: WsClientConfig, deps: WsClientDeps) {
    this.config = config;
    this.deps = deps;
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /**
   * Start: fetch WS endpoint, connect, and send backend_register frame.
   * Returns true if connection succeeded, false otherwise.
   */
  async start(): Promise<boolean> {
    this.stopped = false;
    this.config.log.debug("[ws] fetching WS endpoint...");

    const connectData = await this.fetchWsEndpoint();
    if (!connectData) {
      this.config.log.error("[ws] failed to fetch WS endpoint");
      return false;
    }

    this.wsEndpoint = connectData.endpoint;
    this.pingIntervalMs = connectData.ping_interval_ms;
    this.reconnectIntervalMs = connectData.reconnect_interval_ms;
    this.reconnectNonceMs = connectData.reconnect_nonce_ms;
    this.reconnectMax = connectData.reconnect_max;

    this.config.log.debug(`[ws] got endpoint: ${this.wsEndpoint}`);

    const connected = await this.establishConnection();
    if (!connected) {
      this.config.log.error("[ws] failed to establish WS connection");
      return false;
    }

    return true;
  }

  /**
   * Stop the WebSocket connection without attempting reconnect.
   */
  stop(): void {
    this.stopped = true;
    this.terminateWs();
  }

  /**
   * Send a raw string frame over WebSocket.
   */
  send(raw: string): void {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(raw, (err) => {
        if (err) {
          this.config.log.error(`[ws] send error: ${err.message}`);
        }
      });
    } else {
      this.config.log.warn("[ws] cannot send: WebSocket not open");
    }
  }

  /**
   * Send a message frame.
   */
  sendMessage(frame: MessageFrame): void {
    this.send(serializeFrame(frame));
  }

  /**
   * Send a ping frame (application-layer).
   */
  sendPing(): void {
    this.send(JSON.stringify({ type: "ping" }));
  }

  /**
   * Send a pong frame (application-layer).
   */
  sendPong(): void {
    this.send(JSON.stringify({ type: "pong" }));
  }

  /**
   * Send a list_pairs query.
   */
  sendListPairs(): void {
    this.send(JSON.stringify({ type: "list_pairs" }));
  }

  /**
   * Send a pair_response frame.
   */
  sendPairResponse(accountId: string, approved: boolean): void {
    const frame: PairResponseFrame = {
      type: "pair_response",
      account_id: accountId,
      approved,
      backend_id: this.registeredBackendId ?? this.config.agentId,
      backend_label: this.config.label ?? "OpenClaw",
    };
    this.send(serializeFrame(frame));
  }

  /**
   * Get the registered backend ID.
   */
  getBackendId(): string | null {
    return this.registeredBackendId;
  }

  /**
   * @deprecated use getBackendId()
   */
  getClientId(): string | null {
    return this.getBackendId();
  }

  /**
   * Get WS config for reconnect manager.
   */
  getReconnectConfig(): {
    reconnectIntervalMs: number;
    reconnectNonceMs: number;
    reconnectMax: number;
  } | null {
    if (this.reconnectIntervalMs === null) return null;
    return {
      reconnectIntervalMs: this.reconnectIntervalMs ?? 5_000,
      reconnectNonceMs: this.reconnectNonceMs ?? 30_000,
      reconnectMax: this.reconnectMax ?? -1,
    };
  }

  /**
   * Get the ping interval from Router config.
   */
  getPingIntervalMs(): number | null {
    return this.pingIntervalMs;
  }

  // -------------------------------------------------------------------------
  // Private methods
  // -------------------------------------------------------------------------

  /**
   * POST /api/ws/connect to get the WebSocket endpoint.
   */
  private async fetchWsEndpoint(): Promise<WsConnectResponse["data"] | null> {
    const url = `${this.config.baseUrl}${WS_CONNECT_PATH}`;

    let response: Response;
    try {
      response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          agent_id: this.config.agentId,
          token: this.config.token,
          tenant_id: this.config.tenantId,
        }),
      });
    } catch (err) {
      this.config.log.error(`[ws] /api/ws/connect failed: ${err}`);
      return null;
    }

    if (!response.ok) {
      this.config.log.error(`[ws] /api/ws/connect returned ${response.status}`);
      return null;
    }

    let data: WsConnectResponse;
    try {
      data = (await response.json()) as WsConnectResponse;
    } catch {
      this.config.log.error("[ws] /api/ws/connect: invalid JSON response");
      return null;
    }

    if (data.code !== 0) {
      this.config.log.error(`[ws] /api/ws/connect code=${data.code}`);
      return null;
    }

    return data.data;
  }

  /**
   * Establish the WebSocket connection and attach handlers.
   */
  private async establishConnection(): Promise<boolean> {
    if (!this.wsEndpoint) return false;

    return new Promise((resolve) => {
      let ws: WebSocket;
      try {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        ws = new WebSocket(this.wsEndpoint!, { agent: this.config.agent as any });
      } catch (err) {
        this.config.log.error(`[ws] new WebSocket failed: ${err}`);
        resolve(false);
        return;
      }

      this.ws = ws;

      ws.on("open", () => {
        this.config.log.debug("[ws] WebSocket open");
        this.sendRegisterFrame();
      });

      ws.on("message", (data: WebSocket.RawData) => {
        this.handleMessage(data);
      });

      ws.on("pong", () => {
        // WebSocket protocol-level pong (opcode 0xA)
        this.deps.onRouterPong();
      });

      ws.on("error", (err: Error) => {
        this.config.log.error(`[ws] WebSocket error: ${err.message}`);
        this.deps.onWsError(err);
      });

      ws.on("close", (code: number, reason: Buffer) => {
        this.config.log.debug(`[ws] WebSocket closed: code=${code} reason=${reason.toString()}`);
        this.deps.onClose();
      });

      // Timeout for connection
      const timeout = setTimeout(() => {
        if (ws.readyState !== WebSocket.OPEN) {
          this.config.log.error("[ws] connection timeout");
          ws.terminate();
          resolve(false);
        }
      }, 15_000);

      ws.on("open", () => {
        clearTimeout(timeout);
        resolve(true);
      });
    });
  }

  /**
   * Send the backend_register frame after WS connection is established.
   */
  private sendRegisterFrame(): void {
    const frame: RegisterFrame = {
      type: "backend_register",
      backend_id: this.config.agentId,
      backend_token: this.config.token,
      backend_label: this.config.label ?? "OpenClaw",
    };
    this.send(serializeFrame(frame));
    this.config.log.debug("[ws] backend_register frame sent");
  }

  /**
   * Handle incoming WebSocket message (text or binary).
   */
  private handleMessage(data: WebSocket.RawData): void {
    let raw: string;
    if (typeof data === "string") {
      raw = data;
    } else if (Buffer.isBuffer(data)) {
      raw = data.toString("utf-8");
    } else if (data instanceof Uint8Array) {
      raw = Buffer.from(data).toString("utf-8");
    } else if (data instanceof ArrayBuffer) {
      raw = Buffer.from(data).toString("utf-8");
    } else if (Array.isArray(data)) {
      // Array of buffers
      raw = Buffer.concat(data as Buffer[]).toString("utf-8");
    } else {
      raw = String(data);
    }

    let frame: IncomingFrame;
    try {
      frame = parseFrame(raw);
    } catch (err) {
      if (err instanceof FrameParseError) {
        this.config.log.warn(`[ws] failed to parse frame: ${err.message}`);
      } else {
        this.config.log.error(`[ws] unexpected parse error: ${err}`);
      }
      return;
    }

    this.dispatchFrame(frame);
  }

  /**
   * Dispatch a parsed frame to the appropriate handler.
   */
  private dispatchFrame(frame: IncomingFrame): void {
    switch (frame.type) {
      case "backend_registered":
        this.handleRegistered(frame as RegisteredFrame);
        break;
      case "error":
        this.handleError(frame as RegisterErrorFrame | ErrorFrame);
        break;
      case "message":
        this.handleMessageFrame(frame as MessageFrame);
        break;
      case "pong":
        // Application-layer pong - treat same as router pong
        this.deps.onRouterPong();
        break;
      case "pair_request":
        this.deps.onPairRequest(frame as PairRequestFrame);
        break;
      case "pairs_list":
        this.deps.onPairsList(frame as PairsListFrame);
        break;
      default:
        this.config.log.debug(`[ws] unhandled frame type: ${(frame as IncomingFrame).type}`);
    }
  }

  private handleRegistered(frame: RegisteredFrame): void {
    if (frame.success) {
      this.registeredBackendId = frame.backend_id;
      this.config.log.info(`[ws] registered as ${this.registeredBackendId}`);
      this.deps.onReady(frame.backend_id);
    }
  }

  private handleMessageFrame(frame: MessageFrame): void {
    const ackId = this.deliveryAckId(frame);
    if (ackId) {
      const ackFrame: MessageAckFrame = { type: "message_ack", message_id: ackId };
      this.send(serializeFrame(ackFrame));
    }
    const key = this.receivedMessageKey(frame);
    if (key && !this.rememberReceivedMessageKey(key)) {
      this.config.log.debug(`[ws] duplicate message ignored: ${key}`);
      return;
    }
    this.deps.onMessage(frame);
  }

  private deliveryAckId(frame: MessageFrame): string | undefined {
    if (frame.seq !== undefined) return String(frame.seq);
    return frame.message_id;
  }

  private receivedMessageKey(frame: MessageFrame): string | undefined {
    if (frame.message_id) return `message_id:${frame.message_id}`;
    if (frame.seq !== undefined) return `seq:${frame.seq}`;
    return undefined;
  }

  private rememberReceivedMessageKey(key: string): boolean {
    if (this.receivedMessageKeys.has(key)) return false;
    this.receivedMessageKeys.add(key);
    this.receivedMessageKeyOrder.push(key);
    while (this.receivedMessageKeyOrder.length > 500) {
      const removed = this.receivedMessageKeyOrder.shift();
      if (removed) this.receivedMessageKeys.delete(removed);
    }
    return true;
  }

  private handleError(frame: RegisterErrorFrame | ErrorFrame): void {
    this.config.log.error(`[ws] error from router: code=${frame.code} message=${frame.message}`);
    this.deps.onError(frame);
  }

  private terminateWs(): void {
    if (this.ws) {
      this.ws.removeAllListeners();
      try {
        this.ws.terminate();
      } catch {
        // Ignore
      }
      this.ws = null;
    }
  }
}
