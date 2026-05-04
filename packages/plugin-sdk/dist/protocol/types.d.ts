/**
 * Protocol frame types for OpenClaw Plugin-Router communication.
 * These types define all JSON frames exchanged over WebSocket.
 */
/** Frame sent by Plugin to register with Router */
export interface RegisterFrame {
    type: "register";
    client_type: "backend";
    client_id: string;
    label: string;
    token: string;
}
/** Frame sent by Router on successful registration */
export interface RegisteredFrame {
    type: "registered";
    client_id: string;
    client_type: "backend";
    success: true;
}
/** Frame sent by Router on registration failure */
export interface RegisterErrorFrame {
    type: "error";
    code: string;
    message: string;
}
/** Content type for message frames */
export type MessageContentType = "text" | "command" | "command_result" | "event";
/** Bidirectional message frame */
export interface MessageFrame {
    type: "message";
    from: string;
    to: string;
    device_id?: string;
    content: string;
    content_type: MessageContentType;
    timestamp: string;
    seq?: number;
}
/** Acknowledgment frame for seq */
export interface AckFrame {
    type: "ack";
    seq: number;
}
/** Delivery failure notification */
export interface DeliveryFailedFrame {
    type: "delivery_failed";
    seq: number;
    reason: string;
}
/** Heartbeat ping request */
export interface PingFrame {
    type: "ping";
}
/** Heartbeat pong response */
export interface PongFrame {
    type: "pong";
}
/** Query paired devices */
export interface ListPairsFrame {
    type: "list_pairs";
}
/** Response with paired devices list */
export interface PairsListFrame {
    type: "pairs_list";
    pairs: PairedDevice[];
}
/** Paired device entry */
export interface PairedDevice {
    app_id: string;
    app_label: string;
    created_at: string;
}
/** Incoming pair request from App */
export interface PairRequestFrame {
    type: "pair_request";
    from_app_id: string;
    from_app_label: string;
    from_app_metadata: Record<string, unknown>;
    seq?: number;
}
/** Plugin's response to pair request */
export interface PairResponseFrame {
    type: "pair_response";
    target_app_id: string;
    approve: boolean;
    backend_id: string;
}
/** Notification that App was unpaired */
export interface UnpairedFrame {
    type: "unpaired";
    app_id: string;
}
/** Notification that App disconnected */
export interface DeviceDisconnectedFrame {
    type: "device_disconnected";
    app_id: string;
}
/** Generic error frame from Router */
export interface ErrorFrame {
    type: "error";
    code: string;
    message: string;
}
export type IncomingFrame = RegisteredFrame | RegisterErrorFrame | MessageFrame | AckFrame | DeliveryFailedFrame | PongFrame | PairsListFrame | PairRequestFrame | UnpairedFrame | DeviceDisconnectedFrame | ErrorFrame;
export type OutgoingFrame = RegisterFrame | MessageFrame | AckFrame | PingFrame | PongFrame | ListPairsFrame | PairResponseFrame;
/** Payload for command result callback */
export interface CommandResultPayload {
    success: boolean;
    result?: unknown;
    durationMs: number;
}
/** Payload for event push */
export interface EventPushPayload {
    backend_id: string;
    event: string;
    data: unknown;
}
export interface WsConnectResponse {
    code: number;
    data: {
        endpoint: string;
        ping_interval_ms: number;
        reconnect_interval_ms: number;
        reconnect_nonce_ms: number;
        reconnect_max: number;
    };
}
export interface WsEndpointParams {
    device_id?: string;
    service_id?: string;
}
//# sourceMappingURL=types.d.ts.map