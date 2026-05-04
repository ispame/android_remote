/**
 * Serialize outgoing frames to JSON strings.
 */
import type { OutgoingFrame, RegisterFrame, MessageFrame, AckFrame, PingFrame, PongFrame, ListPairsFrame, PairResponseFrame } from "./types.js";
/**
 * Serialize any outgoing frame to a JSON string.
 * Throws if the frame type is unknown.
 */
export declare function serializeFrame(frame: OutgoingFrame): string;
/**
 * Serialize a register frame.
 */
export declare function serializeRegister(frame: RegisterFrame): string;
/**
 * Serialize a message frame.
 */
export declare function serializeMessage(frame: MessageFrame): string;
/**
 * Serialize an ack frame.
 */
export declare function serializeAck(frame: AckFrame): string;
/**
 * Serialize a ping frame.
 */
export declare function serializePing(frame: PingFrame): string;
/**
 * Serialize a pong frame.
 */
export declare function serializePong(frame: PongFrame): string;
/**
 * Serialize a list_pairs frame.
 */
export declare function serializeListPairs(frame: ListPairsFrame): string;
/**
 * Serialize a pair_response frame.
 */
export declare function serializePairResponse(frame: PairResponseFrame): string;
//# sourceMappingURL=serialize.d.ts.map