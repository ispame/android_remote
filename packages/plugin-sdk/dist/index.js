/**
 * OpenClaw Plugin SDK
 *
 * A TypeScript SDK for building OpenClaw Plugins that connect to the
 * GatewayRouter via a single outgoing WebSocket connection.
 *
 * Usage:
 * ```ts
 * import { GatewayChannel } from "@openclaw/plugin-sdk";
 *
 * const channel = new GatewayChannel({
 *   baseUrl: "https://boson-tech.top",
 *   agentId: "my-agent",
 *   token: "plugin-token",
 *   tenantId: "tenant-1",
 * });
 *
 * channel.on("message", (msg) => {
 *   console.log("message from", msg.account_id, ":", msg.content);
 * });
 *
 * channel.on("pair_request", (req) => {
 *   console.log("pair request from", req.terminal_label);
 *   channel.approvePairRequest(req.account_id!, true);
 * });
 *
 * await channel.start();
 * ```
 */
// Core channel
export { GatewayChannel } from "./GatewayChannel.js";
// Sub-components (exported for advanced usage / testing)
export { WsClient } from "./WsClient.js";
export { HttpClient } from "./http-client.js";
export { ReconnectManager } from "./reconnect.js";
export { HeartbeatManager } from "./heartbeat.js";
export { createPrefixedLogger, noopLogger } from "./logger.js";
// Protocol serialization/parsing
export { serializeFrame, serializeMessage, serializeAck } from "./protocol/serialize.js";
export { parseFrame, parseFrameSafe, FrameParseError } from "./protocol/parse.js";
//# sourceMappingURL=index.js.map