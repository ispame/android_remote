/**
 * WebSocket client that manages the Plugin's outgoing WS connection to Router.
 *
 * Responsibilities:
 * - Fetch WS endpoint via HTTP POST /api/ws/connect
 * - Establish and maintain the WebSocket connection
 * - Send the register frame after connection
 * - Handle incoming frames (parse + dispatch)
 * - Handle pong detection for heartbeat
 * - Trigger reconnect on unexpected close/error
 *
 * Does NOT handle reconnection scheduling — that is delegated to ReconnectManager.
 */
import type { Logger } from "./logger.js";
import type { MessageFrame, PairRequestFrame, PairsListFrame, ErrorFrame } from "./protocol/types.js";
export interface WsClientConfig {
    /** Base URL of Router (e.g., https://boson-tech.top). */
    baseUrl: string;
    /** Agent ID for this plugin. */
    agentId: string;
    /** Plugin token for authentication. */
    token: string;
    /** Tenant ID. */
    tenantId: string;
    /** Plugin label (sent in register frame). */
    label?: string;
    /** Custom WebSocket agent (for proxy, TLS, etc.). */
    agent?: any;
    /** Logger instance. */
    log: Logger;
}
export interface WsClientDeps {
    /** Called when connection is established and registered. */
    onReady: (clientId: string) => void;
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
/**
 * WebSocket client for Plugin-Router communication.
 */
export declare class WsClient {
    private config;
    private deps;
    private ws;
    private registeredClientId;
    private stopped;
    private wsEndpoint;
    private pingIntervalMs;
    private reconnectIntervalMs;
    private reconnectNonceMs;
    private reconnectMax;
    constructor(config: WsClientConfig, deps: WsClientDeps);
    /**
     * Start: fetch WS endpoint, connect, and send register frame.
     * Returns true if connection succeeded, false otherwise.
     */
    start(): Promise<boolean>;
    /**
     * Stop the WebSocket connection without attempting reconnect.
     */
    stop(): void;
    /**
     * Send a raw string frame over WebSocket.
     */
    send(raw: string): void;
    /**
     * Send a message frame.
     */
    sendMessage(frame: MessageFrame): void;
    /**
     * Send a ping frame (application-layer).
     */
    sendPing(): void;
    /**
     * Send a pong frame (application-layer).
     */
    sendPong(): void;
    /**
     * Send a list_pairs query.
     */
    sendListPairs(): void;
    /**
     * Send a pair_response frame.
     */
    sendPairResponse(targetAppId: string, approve: boolean): void;
    /**
     * Get the registered client ID (assigned by Router after register).
     */
    getClientId(): string | null;
    /**
     * Get WS config for reconnect manager.
     */
    getReconnectConfig(): {
        reconnectIntervalMs: number;
        reconnectNonceMs: number;
        reconnectMax: number;
    } | null;
    /**
     * Get the ping interval from Router config.
     */
    getPingIntervalMs(): number | null;
    /**
     * POST /api/ws/connect to get the WebSocket endpoint.
     */
    private fetchWsEndpoint;
    /**
     * Establish the WebSocket connection and attach handlers.
     */
    private establishConnection;
    /**
     * Send the register frame after WS connection is established.
     */
    private sendRegisterFrame;
    /**
     * Handle incoming WebSocket message (text or binary).
     */
    private handleMessage;
    /**
     * Dispatch a parsed frame to the appropriate handler.
     */
    private dispatchFrame;
    private handleRegistered;
    private handleError;
    private terminateWs;
}
//# sourceMappingURL=WsClient.d.ts.map