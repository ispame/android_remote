/**
 * GatewayChannel — main entry point for OpenClaw Plugin SDK.
 *
 * Ties together:
 *   WsClient      — WebSocket connection management
 *   ReconnectManager — reconnection with exponential backoff
 *   HeartbeatManager — pong detection for heartbeat
 *   HttpClient    — HTTP callbacks (command result, event push)
 *
 * Usage:
 * ```ts
 * const channel = new GatewayChannel({
 *   baseUrl: "https://boson-tech.top",
 *   agentId: "my-agent",
 *   token: "plugin-token",
 *   tenantId: "tenant-1",
 *   log: console,
 * });
 *
 * channel.on("message", (msg) => { ... });
 * channel.on("pair_request", (req) => { ... });
 *
 * await channel.start();
 * // ...
 * await channel.stop();
 * ```
 */

import { WsClient, type WsClientConfig, type WsClientDeps } from "./WsClient.js";
import { ReconnectManager, type ReconnectConfig } from "./reconnect.js";
import { HeartbeatManager, type HeartbeatConfig } from "./heartbeat.js";
import { HttpClient, type AiChatParams, type AiChatResponse, type HttpClientConfig } from "./http-client.js";
import type { Logger } from "./logger.js";
import { createPrefixedLogger } from "./logger.js";
import type {
  MessageFrame,
  PairRequestFrame,
  PairsListFrame,
  ErrorFrame,
  PairedDevice,
  HistoryRequestFrame,
} from "./protocol/types.js";

export interface GatewayChannelConfig {
  /** Router base URL (e.g., https://boson-tech.top). */
  baseUrl: string;
  /** Agent ID for this plugin. */
  agentId: string;
  /** Plugin token. */
  token: string;
  /** Tenant ID. */
  tenantId: string;
  /** Plugin label (default: "OpenClaw"). */
  label?: string;
  /** Auto reconnect on disconnect (default: true). */
  autoReconnect?: boolean;
  /** Custom logger. */
  log?: Logger;
}

export type GatewayChannelEventMap = {
  /** Emitted when the plugin is registered and ready. */
  ready: (backendId: string) => void;
  /** Emitted when a message is received from an App. */
  message: (frame: MessageFrame) => void;
  /** Emitted when a pairing request arrives. */
  pair_request: (frame: PairRequestFrame) => void;
  /** Emitted when the paired device list is received. */
  pairs_list: (devices: PairedDevice[]) => void;
  /** Emitted when an error frame is received. */
  error: (frame: ErrorFrame) => void;
  /** Emitted when the connection is lost. */
  disconnected: () => void;
  /** Emitted on reconnection success. */
  reconnected: (backendId: string) => void;
};

type EventKey = keyof GatewayChannelEventMap;

const DEFAULT_LABEL = "OpenClaw";
const DEFAULT_AUTO_RECONNECT = true;

export type ConnectionState = "idle" | "connecting" | "connected" | "reconnecting" | "stopped";

export type GatewayAiChatParams = Omit<AiChatParams, "backendId"> & {
  backendId?: string;
};

/**
 * GatewayChannel — main SDK class.
 */
export class GatewayChannel {
  private config: Required<GatewayChannelConfig>;
  private logger: Logger;

  private wsClient: WsClient;
  private httpClient: HttpClient;
  private reconnectManager: ReconnectManager;
  private heartbeatManager: HeartbeatManager;
  readonly ai: {
    chat: (params: GatewayAiChatParams) => Promise<AiChatResponse>;
  };

  private state: ConnectionState = "idle";
  private backendId: string | null = null;

  // Event handlers
  private handlers: Map<EventKey, Set<GatewayChannelEventMap[EventKey]>> = new Map();

  constructor(config: GatewayChannelConfig) {
    this.config = {
      baseUrl: config.baseUrl.replace(/\/+$/, ""),
      agentId: config.agentId,
      token: config.token,
      tenantId: config.tenantId,
      label: config.label ?? DEFAULT_LABEL,
      autoReconnect: config.autoReconnect ?? DEFAULT_AUTO_RECONNECT,
      log: config.log ?? createPrefixedLogger("GatewayChannel"),
    };
    this.logger = this.config.log;

    // Build sub-component configs
    const httpConfig: HttpClientConfig = {
      baseUrl: this.config.baseUrl,
      token: this.config.token,
    };
    this.httpClient = new HttpClient(httpConfig);
    this.ai = {
      chat: async (params) => {
        const backendId = params.backendId ?? this.backendId;
        if (!backendId) {
          throw new Error("GatewayChannel is not registered; cannot call Router AI chat");
        }
        return await this.httpClient.chat({
          ...params,
          backendId,
        });
      },
    };

    // Build WsClient deps
    const wsDeps = this.buildWsClientDeps();

    // Build WsClient config
    const wsConfig: WsClientConfig = {
      baseUrl: this.config.baseUrl,
      agentId: this.config.agentId,
      token: this.config.token,
      tenantId: this.config.tenantId,
      label: this.config.label,
      log: this.logger,
    };
    this.wsClient = new WsClient(wsConfig, wsDeps);

    // Build reconnect manager deps
    const reconnectDeps = {
      doReconnect: async () => {
        this.state = "reconnecting";
        const success = await this.wsClient.start();
        return success;
      },
      log: this.logger,
    };
    const reconnectConfig: Partial<ReconnectConfig> = {
      autoReconnect: this.config.autoReconnect,
    };
    this.reconnectManager = new ReconnectManager(reconnectConfig, reconnectDeps);

    // Build heartbeat manager deps
    const heartbeatDeps = {
      sendPong: () => {
        this.wsClient.sendPong();
      },
      onDeadConnection: () => {
        this.logger.warn("[channel] heartbeat: dead connection detected, triggering reconnect");
        this.wsClient.stop();
        this.reconnectManager.onDisconnected();
      },
      log: this.logger,
    };
    const heartbeatConfig: Partial<HeartbeatConfig> = {};
    this.heartbeatManager = new HeartbeatManager(heartbeatConfig, heartbeatDeps);
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /**
   * Start the channel: connect to Router and register.
   */
  async start(): Promise<void> {
    if (this.state === "connected" || this.state === "connecting") {
      this.logger.debug("[channel] already started");
      return;
    }

    this.state = "connecting";
    this.logger.info("[channel] starting...");

    const success = await this.wsClient.start();
    if (!success) {
      this.state = "idle";
      this.logger.error("[channel] initial connection failed");
      // Trigger reconnect if autoReconnect is enabled
      this.reconnectManager.onDisconnected();
      return;
    }

    // Note: 'ready' event will be emitted by wsClient via onReady callback
  }

  /**
   * Stop the channel and cancel all reconnection attempts.
   */
  async stop(): Promise<void> {
    this.logger.info("[channel] stopping...");
    this.state = "stopped";
    this.heartbeatManager.stop();
    this.reconnectManager.stop();
    this.wsClient.stop();
    this.backendId = null;
  }

  /**
   * Register an event handler.
   */
  on<K extends EventKey>(event: K, handler: GatewayChannelEventMap[K]): void {
    if (!this.handlers.has(event)) {
      this.handlers.set(event, new Set());
    }
    this.handlers.get(event)!.add(handler);
  }

  /**
   * Remove an event handler.
   */
  off<K extends EventKey>(event: K, handler: GatewayChannelEventMap[K]): void {
    this.handlers.get(event)?.delete(handler);
  }

  /**
   * Send a message to the active terminal for an account.
   */
  sendMessage(accountId: string, content: string, contentType: MessageFrame["content_type"] = "text"): void {
    if (!this.backendId) {
      this.logger.warn("[channel] cannot send: not registered");
      return;
    }

    const frame: MessageFrame = {
      type: "message",
      account_id: accountId,
      backend_id: this.backendId,
      message_id: `${Date.now()}`,
      content,
      content_type: contentType,
      timestamp: new Date().toISOString(),
    };

    this.wsClient.sendMessage(frame);
  }

  /**
   * Send a command result callback via HTTP.
   */
  async sendCommandResult(
    requestId: string,
    success: boolean,
    result?: unknown,
    durationMs?: number
  ): Promise<void> {
    await this.httpClient.reportCommandResult({
      requestId,
      success,
      result,
      durationMs: durationMs ?? 0,
    });
  }

  /**
   * Push an event to paired Apps via HTTP.
   */
  async pushEvent(event: string, data: unknown): Promise<void> {
    if (!this.backendId) {
      this.logger.warn("[channel] cannot push event: not registered");
      return;
    }

    await this.httpClient.pushEvent({
      backendId: this.backendId,
      event,
      data,
    });
  }

  /**
   * Approve or reject a pairing request.
   */
  approvePairRequest(accountId: string, approve: boolean): void {
    this.wsClient.sendPairResponse(accountId, approve);
  }

  /**
   * Query the list of paired devices.
   */
  listPairs(): void {
    this.wsClient.sendListPairs();
  }

  /**
   * Request history for one account/backend conversation.
   */
  requestHistory(accountId: string, sessionKey = "current", beforeTimestamp?: string, limit?: number): void {
    if (!this.backendId) {
      this.logger.warn("[channel] cannot request history: not registered");
      return;
    }

    const frame: HistoryRequestFrame = {
      type: "history_request",
      account_id: accountId,
      backend_id: this.backendId,
      session_key: sessionKey,
      before_timestamp: beforeTimestamp,
      limit,
    };
    this.wsClient.send(JSON.stringify(frame));
  }

  /**
   * Get the registered backend ID.
   */
  getBackendId(): string | null {
    return this.backendId;
  }

  /**
   * @deprecated use getBackendId()
   */
  getClientId(): string | null {
    return this.getBackendId();
  }

  /**
   * Get the current connection state.
   */
  getState(): ConnectionState {
    return this.state;
  }

  // -------------------------------------------------------------------------
  // Private methods
  // -------------------------------------------------------------------------

  private buildWsClientDeps(): WsClientDeps {
    return {
      onReady: (backendId: string) => {
        const wasConnected = this.backendId !== null;
        this.backendId = backendId;
        this.state = "connected";
        this.reconnectManager.reset();

        // Start heartbeat with ping interval from router
        const pingInterval = this.wsClient.getPingIntervalMs();
        if (pingInterval) {
          this.heartbeatManager.setPingInterval(pingInterval);
        }
        this.heartbeatManager.start();

        const isReconnect = wasConnected && this.handlers.get("reconnected") !== undefined;
        if (isReconnect) {
          this.logger.info(`[channel] reconnected as ${backendId}`);
          this.emit("reconnected", backendId);
        } else {
          this.logger.info(`[channel] ready as ${backendId}`);
        }
        this.emit("ready", backendId);
      },

      onMessage: (frame: MessageFrame) => {
        this.emit("message", frame);
      },

      onPairRequest: (frame: PairRequestFrame) => {
        this.logger.info(`[channel] pair request from ${frame.terminal_label ?? frame.account_id ?? "unknown"} (${frame.account_id ?? "unknown"})`);
        this.emit("pair_request", frame);
      },

      onPairsList: (frame: PairsListFrame) => {
        this.logger.debug(`[channel] pairs list: ${frame.backends.length} backend(s)`);
        this.emit("pairs_list", frame.backends);
      },

      onError: (frame: ErrorFrame) => {
        // On INVALID_TOKEN error, stop reconnecting
        if (frame.code === "INVALID_TOKEN") {
          this.logger.error(`[channel] token invalid, stopping: ${frame.message}`);
          void this.stop();
          return;
        }
        this.emit("error", frame);
      },

      onClose: () => {
        this.heartbeatManager.stop();
        if (this.state === "stopped") return;

        this.logger.warn("[channel] WebSocket closed");
        this.state = "reconnecting";
        this.emit("disconnected");
        this.reconnectManager.onDisconnected();
      },

      onWsError: (err: Error) => {
        this.logger.error(`[channel] WebSocket error: ${err.message}`);
      },

      onRouterPong: () => {
        this.heartbeatManager.onRouterPong();
      },
    };
  }

  private emit<K extends EventKey>(event: K, ...args: Parameters<GatewayChannelEventMap[K]>): void {
    const handlers = this.handlers.get(event);
    if (handlers) {
      for (const handler of handlers) {
        try {
          (handler as (...args: unknown[]) => void)(...args);
        } catch (err) {
          this.logger.error(`[channel] event handler error (${event}): ${err}`);
        }
      }
    }
  }
}
