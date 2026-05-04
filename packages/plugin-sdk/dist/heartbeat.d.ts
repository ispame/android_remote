/**
 * Heartbeat management for WebSocket connection.
 *
 * Router sends WebSocket ping frames (opcode 0x9) every pingIntervalMs.
 * Plugin must respond with pong (opcode 0xA).
 *
 * Also supports application-layer JSON ping/pong:
 *   { "type": "ping" }  /  { "type": "pong" }
 *
 * If no ping/pong is received for more than pingTimeoutMs,
 * the connection is considered dead and reconnect is triggered.
 */
export interface HeartbeatConfig {
    /** Interval at which Router sends pings (ms). */
    pingIntervalMs: number;
    /** Timeout after which missing pong triggers reconnect (ms). */
    pingTimeoutMs: number;
}
export interface HeartbeatCallbacks {
    /** Send an application-layer pong response. */
    sendPong: () => void;
    /** Trigger reconnection. */
    onDeadConnection: () => void;
    /** Optional logger. */
    log?: {
        info: (msg: string) => void;
        debug: (msg: string) => void;
        warn: (msg: string) => void;
        error: (msg: string) => void;
    };
}
/**
 * Manages heartbeat ping/pong detection.
 */
export declare class HeartbeatManager {
    private config;
    private callbacks;
    private lastPongAt;
    private pingTimer;
    private pongTimer;
    private stopped;
    constructor(config: Partial<HeartbeatConfig>, callbacks: HeartbeatCallbacks);
    /**
     * Call when a WebSocket pong (opcode 0xA) is received from Router.
     */
    onRouterPong(): void;
    /**
     * Call when an application-layer pong frame is received.
     */
    onApplicationPong(): void;
    /**
     * Call when an application-layer ping is received.
     * Replies with a pong if the WebSocket ping/pong mechanism isn't being used.
     */
    onApplicationPing(): void;
    /**
     * Start the heartbeat monitor.
     * Sets up a timer to detect dead connections.
     */
    start(): void;
    /**
     * Stop the heartbeat monitor.
     */
    stop(): void;
    /**
     * Reset the pong timeout timer.
     * Called whenever a pong is received.
     */
    private resetPongTimer;
    /**
     * Update the ping interval (e.g., when received from Router).
     */
    setPingInterval(pingIntervalMs: number): void;
    /**
     * Get time since last pong (for diagnostics).
     */
    getTimeSinceLastPong(): number;
}
//# sourceMappingURL=heartbeat.d.ts.map