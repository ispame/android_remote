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
import { type AiChatParams, type AiChatResponse } from "./http-client.js";
import type { Logger } from "./logger.js";
import type { MessageFrame, PairRequestFrame, ErrorFrame, PairedDevice } from "./protocol/types.js";
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
export type ConnectionState = "idle" | "connecting" | "connected" | "reconnecting" | "stopped";
export type GatewayAiChatParams = Omit<AiChatParams, "backendId"> & {
    backendId?: string;
};
/**
 * GatewayChannel — main SDK class.
 */
export declare class GatewayChannel {
    private config;
    private logger;
    private wsClient;
    private httpClient;
    private reconnectManager;
    private heartbeatManager;
    readonly ai: {
        chat: (params: GatewayAiChatParams) => Promise<AiChatResponse>;
    };
    private state;
    private backendId;
    private handlers;
    constructor(config: GatewayChannelConfig);
    /**
     * Start the channel: connect to Router and register.
     */
    start(): Promise<void>;
    /**
     * Stop the channel and cancel all reconnection attempts.
     */
    stop(): Promise<void>;
    /**
     * Register an event handler.
     */
    on<K extends EventKey>(event: K, handler: GatewayChannelEventMap[K]): void;
    /**
     * Remove an event handler.
     */
    off<K extends EventKey>(event: K, handler: GatewayChannelEventMap[K]): void;
    /**
     * Send a message to the active terminal for an account.
     */
    sendMessage(accountId: string, content: string, contentType?: MessageFrame["content_type"]): void;
    /**
     * Send a command result callback via HTTP.
     */
    sendCommandResult(requestId: string, success: boolean, result?: unknown, durationMs?: number): Promise<void>;
    /**
     * Push an event to paired Apps via HTTP.
     */
    pushEvent(event: string, data: unknown): Promise<void>;
    /**
     * Approve or reject a pairing request.
     */
    approvePairRequest(accountId: string, approve: boolean): void;
    /**
     * Query the list of paired devices.
     */
    listPairs(): void;
    /**
     * Request history for one account/backend conversation.
     */
    requestHistory(accountId: string, sessionKey?: string, beforeTimestamp?: string, limit?: number): void;
    /**
     * Get the registered backend ID.
     */
    getBackendId(): string | null;
    /**
     * @deprecated use getBackendId()
     */
    getClientId(): string | null;
    /**
     * Get the current connection state.
     */
    getState(): ConnectionState;
    private buildWsClientDeps;
    private emit;
}
export {};
//# sourceMappingURL=GatewayChannel.d.ts.map