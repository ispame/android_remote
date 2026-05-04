/**
 * Serialize outgoing frames to JSON strings.
 */

import type {
  OutgoingFrame,
  RegisterFrame,
  MessageFrame,
  AckFrame,
  PingFrame,
  PongFrame,
  ListPairsFrame,
  PairResponseFrame,
} from "./types.js";

/**
 * Serialize any outgoing frame to a JSON string.
 * Throws if the frame type is unknown.
 */
export function serializeFrame(frame: OutgoingFrame): string {
  return JSON.stringify(frame);
}

/**
 * Serialize a register frame.
 */
export function serializeRegister(frame: RegisterFrame): string {
  return JSON.stringify(frame);
}

/**
 * Serialize a message frame.
 */
export function serializeMessage(frame: MessageFrame): string {
  return JSON.stringify(frame);
}

/**
 * Serialize an ack frame.
 */
export function serializeAck(frame: AckFrame): string {
  return JSON.stringify(frame);
}

/**
 * Serialize a ping frame.
 */
export function serializePing(frame: PingFrame): string {
  return JSON.stringify(frame);
}

/**
 * Serialize a pong frame.
 */
export function serializePong(frame: PongFrame): string {
  return JSON.stringify(frame);
}

/**
 * Serialize a list_pairs frame.
 */
export function serializeListPairs(frame: ListPairsFrame): string {
  return JSON.stringify(frame);
}

/**
 * Serialize a pair_response frame.
 */
export function serializePairResponse(frame: PairResponseFrame): string {
  return JSON.stringify(frame);
}
