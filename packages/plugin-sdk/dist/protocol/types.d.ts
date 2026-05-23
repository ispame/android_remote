/**
 * Thin protocol bridge for the OpenClaw plugin SDK.
 * The canonical wire contract now lives in @openclaw/protocol.
 */
import type { Frame, MessageContentType, BackendRegisterFrame, BackendRegisteredFrame, MessageFrame, MessageAckFrame, MessageDeliveryFailedFrame, PingFrame, PongFrame, PairsListFrame, PairedBackend, PairRequestFrame, PairResponseFrame, UnpairedFrame, AccountSessionActiveFrame, AccountSessionInactiveFrame, ErrorFrame, WsConnectResponse, WsEndpointParams, HistoryRequestFrame, HistoryResponseFrame, SessionPreemptedFrame, HistoryItem } from "@openclaw/protocol";
export type RegisterFrame = BackendRegisterFrame;
export type RegisteredFrame = BackendRegisteredFrame;
export type RegisterErrorFrame = ErrorFrame;
export type AckFrame = MessageAckFrame;
export type DeliveryFailedFrame = MessageDeliveryFailedFrame;
export type PairedDevice = PairedBackend;
export type ListPairsFrame = {
    type: "list_pairs";
};
export type IncomingFrame = Frame;
export type OutgoingFrame = Frame | ListPairsFrame;
export type { Frame, MessageContentType, BackendRegisterFrame, BackendRegisteredFrame, MessageFrame, MessageAckFrame, MessageDeliveryFailedFrame, PingFrame, PongFrame, PairsListFrame, PairedBackend, PairRequestFrame, PairResponseFrame, UnpairedFrame, AccountSessionActiveFrame, AccountSessionInactiveFrame, ErrorFrame, WsConnectResponse, WsEndpointParams, HistoryRequestFrame, HistoryResponseFrame, SessionPreemptedFrame, HistoryItem, };
//# sourceMappingURL=types.d.ts.map