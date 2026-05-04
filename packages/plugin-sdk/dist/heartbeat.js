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
const DEFAULT_PING_INTERVAL_MS = 25_000;
const DEFAULT_PING_TIMEOUT_MS = 30_000;
/**
 * Manages heartbeat ping/pong detection.
 */
export class HeartbeatManager {
    config;
    callbacks;
    lastPongAt = Date.now();
    pingTimer = null;
    pongTimer = null;
    stopped = false;
    constructor(config, callbacks) {
        this.config = {
            pingIntervalMs: config?.pingIntervalMs ?? DEFAULT_PING_INTERVAL_MS,
            pingTimeoutMs: config?.pingTimeoutMs ?? DEFAULT_PING_TIMEOUT_MS,
        };
        this.callbacks = callbacks;
    }
    /**
     * Call when a WebSocket pong (opcode 0xA) is received from Router.
     */
    onRouterPong() {
        this.lastPongAt = Date.now();
        this.resetPongTimer();
        this.callbacks.log?.debug("[heartbeat] router pong received");
    }
    /**
     * Call when an application-layer pong frame is received.
     */
    onApplicationPong() {
        this.lastPongAt = Date.now();
        this.resetPongTimer();
        this.callbacks.log?.debug("[heartbeat] application pong received");
    }
    /**
     * Call when an application-layer ping is received.
     * Replies with a pong if the WebSocket ping/pong mechanism isn't being used.
     */
    onApplicationPing() {
        // Reply with application-layer pong
        this.callbacks.sendPong();
    }
    /**
     * Start the heartbeat monitor.
     * Sets up a timer to detect dead connections.
     */
    start() {
        if (this.stopped)
            return;
        this.lastPongAt = Date.now();
        this.resetPongTimer();
        this.callbacks.log?.debug(`[heartbeat] started (pingInterval=${this.config.pingIntervalMs}ms, pingTimeout=${this.config.pingTimeoutMs}ms)`);
    }
    /**
     * Stop the heartbeat monitor.
     */
    stop() {
        this.stopped = true;
        if (this.pingTimer !== null) {
            clearTimeout(this.pingTimer);
            this.pingTimer = null;
        }
        if (this.pongTimer !== null) {
            clearTimeout(this.pongTimer);
            this.pongTimer = null;
        }
        this.callbacks.log?.debug("[heartbeat] stopped");
    }
    /**
     * Reset the pong timeout timer.
     * Called whenever a pong is received.
     */
    resetPongTimer() {
        if (this.pongTimer !== null) {
            clearTimeout(this.pongTimer);
        }
        if (this.stopped)
            return;
        this.pongTimer = setTimeout(() => {
            const elapsed = Date.now() - this.lastPongAt;
            if (elapsed >= this.config.pingTimeoutMs) {
                this.callbacks.log?.warn(`[heartbeat] no pong received for ${elapsed}ms, connection dead`);
                this.callbacks.onDeadConnection();
            }
        }, this.config.pingTimeoutMs);
    }
    /**
     * Update the ping interval (e.g., when received from Router).
     */
    setPingInterval(pingIntervalMs) {
        this.config.pingIntervalMs = pingIntervalMs;
        this.callbacks.log?.debug(`[heartbeat] pingInterval updated to ${pingIntervalMs}ms`);
    }
    /**
     * Get time since last pong (for diagnostics).
     */
    getTimeSinceLastPong() {
        return Date.now() - this.lastPongAt;
    }
}
//# sourceMappingURL=heartbeat.js.map