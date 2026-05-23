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
export { GatewayChannel, type GatewayChannelConfig, type GatewayChannelEventMap } from "./GatewayChannel.js";
export type { ConnectionState } from "./GatewayChannel.js";

// Sub-components (exported for advanced usage / testing)
export { WsClient, type WsClientConfig, type WsClientDeps } from "./WsClient.js";
export { HttpClient } from "./http-client.js";
export { ReconnectManager } from "./reconnect.js";
export { HeartbeatManager } from "./heartbeat.js";

// Logger
export type { Logger } from "./logger.js";
export { createPrefixedLogger, noopLogger } from "./logger.js";

// Protocol types
export type {
  // Connection frames
  RegisterFrame,
  RegisteredFrame,
  RegisterErrorFrame,
  // Message frames
  MessageFrame,
  MessageContentType,
  AckFrame,
  DeliveryFailedFrame,
  // Heartbeat frames
  PingFrame,
  PongFrame,
  // Pairing frames
  ListPairsFrame,
  PairsListFrame,
  PairedDevice,
  PairRequestFrame,
  PairResponseFrame,
  UnpairedFrame,
  AccountSessionActiveFrame,
  AccountSessionInactiveFrame,
  SessionPreemptedFrame,
  HistoryRequestFrame,
  HistoryResponseFrame,
  HistoryItem,
  // Error frame
  ErrorFrame,
  // Union types
  IncomingFrame,
  OutgoingFrame,
  // WS connect
  WsConnectResponse,
  WsEndpointParams,
} from "./protocol/types.js";

export type { CommandResultParams as CommandResultPayload, EventPushParams as EventPushPayload } from "./http-client.js";

// Protocol serialization/parsing
export { serializeFrame, serializeMessage, serializeAck } from "./protocol/serialize.js";
export { parseFrame, parseFrameSafe, FrameParseError } from "./protocol/parse.js";
