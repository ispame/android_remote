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
import WebSocket from "ws";
import { parseFrame, FrameParseError } from "./protocol/parse.js";
import { serializeFrame } from "./protocol/serialize.js";
const WS_CONNECT_PATH = "/api/ws/connect";
/**
 * WebSocket client for Plugin-Router communication.
 */
export class WsClient {
    config;
    deps;
    ws = null;
    registeredBackendId = null;
    stopped = false;
    receivedMessageKeys = new Set();
    receivedMessageKeyOrder = [];
    // WS config obtained from /api/ws/connect response
    wsEndpoint = null;
    pingIntervalMs = null;
    reconnectIntervalMs = null;
    reconnectNonceMs = null;
    reconnectMax = null;
    constructor(config, deps) {
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
    async start() {
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
    stop() {
        this.stopped = true;
        this.terminateWs();
    }
    /**
     * Send a raw string frame over WebSocket.
     */
    send(raw) {
        if (this.ws && this.ws.readyState === WebSocket.OPEN) {
            this.ws.send(raw, (err) => {
                if (err) {
                    this.config.log.error(`[ws] send error: ${err.message}`);
                }
            });
        }
        else {
            this.config.log.warn("[ws] cannot send: WebSocket not open");
        }
    }
    /**
     * Send a message frame.
     */
    sendMessage(frame) {
        this.send(serializeFrame(frame));
    }
    /**
     * Send a ping frame (application-layer).
     */
    sendPing() {
        this.send(JSON.stringify({ type: "ping" }));
    }
    /**
     * Send a pong frame (application-layer).
     */
    sendPong() {
        this.send(JSON.stringify({ type: "pong" }));
    }
    /**
     * Send a list_pairs query.
     */
    sendListPairs() {
        this.send(JSON.stringify({ type: "list_pairs" }));
    }
    /**
     * Send a pair_response frame.
     */
    sendPairResponse(accountId, approved) {
        const frame = {
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
    getBackendId() {
        return this.registeredBackendId;
    }
    /**
     * @deprecated use getBackendId()
     */
    getClientId() {
        return this.getBackendId();
    }
    /**
     * Get WS config for reconnect manager.
     */
    getReconnectConfig() {
        if (this.reconnectIntervalMs === null)
            return null;
        return {
            reconnectIntervalMs: this.reconnectIntervalMs ?? 5_000,
            reconnectNonceMs: this.reconnectNonceMs ?? 30_000,
            reconnectMax: this.reconnectMax ?? -1,
        };
    }
    /**
     * Get the ping interval from Router config.
     */
    getPingIntervalMs() {
        return this.pingIntervalMs;
    }
    // -------------------------------------------------------------------------
    // Private methods
    // -------------------------------------------------------------------------
    /**
     * POST /api/ws/connect to get the WebSocket endpoint.
     */
    async fetchWsEndpoint() {
        const url = `${this.config.baseUrl}${WS_CONNECT_PATH}`;
        let response;
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
        }
        catch (err) {
            this.config.log.error(`[ws] /api/ws/connect failed: ${err}`);
            return null;
        }
        if (!response.ok) {
            this.config.log.error(`[ws] /api/ws/connect returned ${response.status}`);
            return null;
        }
        let data;
        try {
            data = (await response.json());
        }
        catch {
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
    async establishConnection() {
        if (!this.wsEndpoint)
            return false;
        return new Promise((resolve) => {
            let ws;
            try {
                // eslint-disable-next-line @typescript-eslint/no-explicit-any
                ws = new WebSocket(this.wsEndpoint, { agent: this.config.agent });
            }
            catch (err) {
                this.config.log.error(`[ws] new WebSocket failed: ${err}`);
                resolve(false);
                return;
            }
            this.ws = ws;
            ws.on("open", () => {
                this.config.log.debug("[ws] WebSocket open");
                this.sendRegisterFrame();
            });
            ws.on("message", (data) => {
                this.handleMessage(data);
            });
            ws.on("pong", () => {
                // WebSocket protocol-level pong (opcode 0xA)
                this.deps.onRouterPong();
            });
            ws.on("error", (err) => {
                this.config.log.error(`[ws] WebSocket error: ${err.message}`);
                this.deps.onWsError(err);
            });
            ws.on("close", (code, reason) => {
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
    sendRegisterFrame() {
        const frame = {
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
    handleMessage(data) {
        let raw;
        if (typeof data === "string") {
            raw = data;
        }
        else if (Buffer.isBuffer(data)) {
            raw = data.toString("utf-8");
        }
        else if (data instanceof Uint8Array) {
            raw = Buffer.from(data).toString("utf-8");
        }
        else if (data instanceof ArrayBuffer) {
            raw = Buffer.from(data).toString("utf-8");
        }
        else if (Array.isArray(data)) {
            // Array of buffers
            raw = Buffer.concat(data).toString("utf-8");
        }
        else {
            raw = String(data);
        }
        let frame;
        try {
            frame = parseFrame(raw);
        }
        catch (err) {
            if (err instanceof FrameParseError) {
                this.config.log.warn(`[ws] failed to parse frame: ${err.message}`);
            }
            else {
                this.config.log.error(`[ws] unexpected parse error: ${err}`);
            }
            return;
        }
        this.dispatchFrame(frame);
    }
    /**
     * Dispatch a parsed frame to the appropriate handler.
     */
    dispatchFrame(frame) {
        switch (frame.type) {
            case "backend_registered":
                this.handleRegistered(frame);
                break;
            case "error":
                this.handleError(frame);
                break;
            case "message":
                this.handleMessageFrame(frame);
                break;
            case "pong":
                // Application-layer pong - treat same as router pong
                this.deps.onRouterPong();
                break;
            case "pair_request":
                this.deps.onPairRequest(frame);
                break;
            case "pairs_list":
                this.deps.onPairsList(frame);
                break;
            default:
                this.config.log.debug(`[ws] unhandled frame type: ${frame.type}`);
        }
    }
    handleRegistered(frame) {
        if (frame.success) {
            this.registeredBackendId = frame.backend_id;
            this.config.log.info(`[ws] registered as ${this.registeredBackendId}`);
            this.deps.onReady(frame.backend_id);
        }
    }
    handleMessageFrame(frame) {
        const ackId = this.deliveryAckId(frame);
        if (ackId) {
            const ackFrame = { type: "message_ack", message_id: ackId };
            this.send(serializeFrame(ackFrame));
        }
        const key = this.receivedMessageKey(frame);
        if (key && !this.rememberReceivedMessageKey(key)) {
            this.config.log.debug(`[ws] duplicate message ignored: ${key}`);
            return;
        }
        this.deps.onMessage(frame);
    }
    deliveryAckId(frame) {
        if (frame.seq !== undefined)
            return String(frame.seq);
        return frame.message_id;
    }
    receivedMessageKey(frame) {
        if (frame.message_id)
            return `message_id:${frame.message_id}`;
        if (frame.seq !== undefined)
            return `seq:${frame.seq}`;
        return undefined;
    }
    rememberReceivedMessageKey(key) {
        if (this.receivedMessageKeys.has(key))
            return false;
        this.receivedMessageKeys.add(key);
        this.receivedMessageKeyOrder.push(key);
        while (this.receivedMessageKeyOrder.length > 500) {
            const removed = this.receivedMessageKeyOrder.shift();
            if (removed)
                this.receivedMessageKeys.delete(removed);
        }
        return true;
    }
    handleError(frame) {
        this.config.log.error(`[ws] error from router: code=${frame.code} message=${frame.message}`);
        this.deps.onError(frame);
    }
    terminateWs() {
        if (this.ws) {
            this.ws.removeAllListeners();
            try {
                this.ws.terminate();
            }
            catch {
                // Ignore
            }
            this.ws = null;
        }
    }
}
//# sourceMappingURL=WsClient.js.map