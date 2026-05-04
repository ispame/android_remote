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
const DEFAULT_RECONNECT_INTERVAL_MS = 5_000;
const DEFAULT_RECONNECT_NONCE_MS = 30_000;
const DEFAULT_RECONNECT_MAX = -1;
const MAX_BACKOFF_MS = 30_000;
/**
 * Manages reconnection with exponential backoff and generation tracking.
 */
export class ReconnectManager {
    config;
    callbacks;
    isConnecting = false;
    reconnectCount = 0;
    reconnectTimer = null;
    generation = 0;
    stopped = false;
    constructor(config, callbacks) {
        this.config = {
            reconnectIntervalMs: config?.reconnectIntervalMs ?? DEFAULT_RECONNECT_INTERVAL_MS,
            reconnectNonceMs: config?.reconnectNonceMs ?? DEFAULT_RECONNECT_NONCE_MS,
            reconnectMax: config?.reconnectMax ?? DEFAULT_RECONNECT_MAX,
            autoReconnect: config?.autoReconnect ?? true,
        };
        this.callbacks = callbacks;
    }
    /**
     * Called when the WebSocket connection is lost unexpectedly.
     * Schedules a reconnect if autoReconnect is enabled.
     */
    onDisconnected() {
        if (this.stopped || !this.config.autoReconnect) {
            this.callbacks.log?.debug("[reconnect] autoReconnect disabled, not scheduling reconnect");
            return;
        }
        this.scheduleReconnect();
    }
    /**
     * Called when a reconnection attempt should be made.
     * Uses exponential backoff and respects reconnectMax.
     */
    async attemptReconnect() {
        if (this.stopped) {
            this.callbacks.log?.debug("[reconnect] stopped, skipping reconnect attempt");
            return false;
        }
        if (this.isConnecting) {
            this.callbacks.log?.debug("[reconnect] already connecting, skipping");
            return false;
        }
        // Check reconnectMax
        if (this.config.reconnectMax >= 0 && this.reconnectCount >= this.config.reconnectMax) {
            this.callbacks.log?.warn(`[reconnect] max reconnect attempts (${this.config.reconnectMax}) reached, giving up`);
            return false;
        }
        this.isConnecting = true;
        this.reconnectCount++;
        const currentGeneration = this.generation;
        try {
            const success = await this.callbacks.doReconnect();
            // Discard if generation changed (i.e., stop() was called)
            if (currentGeneration !== this.generation) {
                this.callbacks.log?.debug("[reconnect] generation changed, discarding result");
                return false;
            }
            if (success) {
                this.reconnectCount = 0;
                this.callbacks.log?.info("[reconnect] reconnected successfully");
            }
            else {
                this.callbacks.log?.warn(`[reconnect] attempt ${this.reconnectCount} failed`);
                this.scheduleReconnect();
            }
            return success;
        }
        finally {
            if (currentGeneration === this.generation) {
                this.isConnecting = false;
            }
        }
    }
    /**
     * Schedule the next reconnect attempt with exponential backoff.
     */
    scheduleReconnect() {
        if (this.stopped || !this.config.autoReconnect)
            return;
        // Clear any existing timer
        if (this.reconnectTimer !== null) {
            clearTimeout(this.reconnectTimer);
        }
        // Calculate delay
        const delay = this.calculateDelay();
        this.callbacks.log?.debug(`[reconnect] scheduling next attempt in ${delay}ms (attempt ${this.reconnectCount + 1})`);
        this.reconnectTimer = setTimeout(() => {
            void this.attemptReconnect();
        }, delay);
    }
    /**
     * Calculate backoff delay.
     * First attempt: random(0, reconnectNonceMs)
     * Subsequent: min(reconnectIntervalMs * 2^count + random(0, reconnectNonceMs), 30000)
     */
    calculateDelay() {
        const jitter = Math.random() * this.config.reconnectNonceMs;
        if (this.reconnectCount === 0) {
            // First attempt: just jitter
            return Math.min(jitter, MAX_BACKOFF_MS);
        }
        const exponentialDelay = this.config.reconnectIntervalMs * Math.pow(2, this.reconnectCount - 1);
        return Math.min(exponentialDelay + jitter, MAX_BACKOFF_MS);
    }
    /**
     * Stop reconnection attempts and increment generation.
     * Any in-flight reconnect callbacks will be discarded.
     */
    stop() {
        this.callbacks.log?.debug("[reconnect] stopping");
        this.stopped = true;
        this.generation++;
        if (this.reconnectTimer !== null) {
            clearTimeout(this.reconnectTimer);
            this.reconnectTimer = null;
        }
        this.isConnecting = false;
    }
    /**
     * Reset state after successful connection.
     */
    reset() {
        this.reconnectCount = 0;
        this.isConnecting = false;
    }
    /**
     * Update reconnect configuration (e.g., from Router).
     */
    updateConfig(config) {
        this.config = { ...this.config, ...config };
        this.callbacks.log?.debug("[reconnect] config updated");
    }
    /**
     * Returns whether we are currently trying to connect.
     */
    isReconnecting() {
        return this.isConnecting;
    }
    /**
     * Get current reconnect attempt count.
     */
    getReconnectCount() {
        return this.reconnectCount;
    }
}
//# sourceMappingURL=reconnect.js.map