/**
 * Serialize outgoing frames to JSON strings.
 */
import type { OutgoingFrame, RegisterFrame, MessageFrame, AckFrame, PingFrame, PongFrame, ListPairsFrame, PairResponseFrame } from "./types.js";
export declare function serializeFrame(frame: OutgoingFrame): string;
export declare function serializeRegister(frame: RegisterFrame): string;
export declare function serializeMessage(frame: MessageFrame): string;
export declare function serializeAck(frame: AckFrame): string;
export declare function serializePing(frame: PingFrame): string;
export declare function serializePong(frame: PongFrame): string;
export declare function serializeListPairs(frame: ListPairsFrame): string;
export declare function serializePairResponse(frame: PairResponseFrame): string;
//# sourceMappingURL=serialize.d.ts.map