/**
 * Reconnection logic with exponential backoff.
 *
 * Implements the algorithm from the design doc:
 *   delay = min(reconnectIntervalMs * 2^count + random(0~reconnectNonceMs), 30000)
 *
 * Features:
 * - Exponential backoff
 * - isConnecting guard to prevent concurrent reconnect attempts
 * - generation mechanism to discard stale callbacks on stop()
 * - reconnectMax = -1 means infinite retries
 */
export interface ReconnectConfig {
    /** Base reconnect interval in ms (from Router /api/ws/connect response). */
    reconnectIntervalMs: number;
    /** Jitter upper bound in ms. */
    reconnectNonceMs: number;
    /** Maximum reconnect attempts. -1 means infinite. */
    reconnectMax: number;
    /** Auto reconnect enabled. */
    autoReconnect: boolean;
}
export interface ReconnectCallbacks {
    /** Attempt to reconnect (fetches new WS endpoint + connects). */
    doReconnect: () => Promise<boolean>;
    /** Optional logger. */
    log?: {
        info: (msg: string) => void;
        debug: (msg: string) => void;
        warn: (msg: string) => void;
        error: (msg: string) => void;
    };
}
/**
 * Manages reconnection with exponential backoff and generation tracking.
 */
export declare class ReconnectManager {
    private config;
    private callbacks;
    private isConnecting;
    private reconnectCount;
    private reconnectTimer;
    private generation;
    private stopped;
    constructor(config: Partial<ReconnectConfig>, callbacks: ReconnectCallbacks);
    /**
     * Called when the WebSocket connection is lost unexpectedly.
     * Schedules a reconnect if autoReconnect is enabled.
     */
    onDisconnected(): void;
    /**
     * Called when a reconnection attempt should be made.
     * Uses exponential backoff and respects reconnectMax.
     */
    attemptReconnect(): Promise<boolean>;
    /**
     * Schedule the next reconnect attempt with exponential backoff.
     */
    private scheduleReconnect;
    /**
     * Calculate backoff delay.
     * First attempt: random(0, reconnectNonceMs)
     * Subsequent: min(reconnectIntervalMs * 2^count + random(0, reconnectNonceMs), 30000)
     */
    private calculateDelay;
    /**
     * Stop reconnection attempts and increment generation.
     * Any in-flight reconnect callbacks will be discarded.
     */
    stop(): void;
    /**
     * Reset state after successful connection.
     */
    reset(): void;
    /**
     * Update reconnect configuration (e.g., from Router).
     */
    updateConfig(config: Partial<ReconnectConfig>): void;
    /**
     * Returns whether we are currently trying to connect.
     */
    isReconnecting(): boolean;
    /**
     * Get current reconnect attempt count.
     */
    getReconnectCount(): number;
}
//# sourceMappingURL=reconnect.d.ts.map