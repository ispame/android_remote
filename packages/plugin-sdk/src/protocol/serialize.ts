/**
 * Serialize outgoing frames to JSON strings.
 */

import { serialize } from "@openclaw/protocol";
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

export function serializeFrame(frame: OutgoingFrame): string {
  return serialize(frame as Parameters<typeof serialize>[0]);
}

export function serializeRegister(frame: RegisterFrame): string {
  return serializeFrame(frame);
}

export function serializeMessage(frame: MessageFrame): string {
  return serializeFrame(frame);
}

export function serializeAck(frame: AckFrame): string {
  return serializeFrame(frame);
}

export function serializePing(frame: PingFrame): string {
  return serializeFrame(frame);
}

export function serializePong(frame: PongFrame): string {
  return serializeFrame(frame);
}

export function serializeListPairs(frame: ListPairsFrame): string {
  return serializeFrame(frame);
}

export function serializePairResponse(frame: PairResponseFrame): string {
  return serializeFrame(frame);
}
