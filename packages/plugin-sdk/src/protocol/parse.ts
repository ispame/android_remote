/**
 * Parse incoming JSON frames from Router.
 */

import type {
  IncomingFrame,
  RegisteredFrame,
  RegisterErrorFrame,
  MessageFrame,
  AckFrame,
  DeliveryFailedFrame,
  PongFrame,
  PairsListFrame,
  PairRequestFrame,
  UnpairedFrame,
  DeviceDisconnectedFrame,
  ErrorFrame,
} from "./types.js";

/**
 * Error thrown when a frame cannot be parsed.
 */
export class FrameParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FrameParseError";
  }
}

/**
 * Parse a raw JSON string into an IncomingFrame.
 * Returns null if the frame type is unrecognized (for forward compatibility).
 */
export function parseFrame(raw: string): IncomingFrame {
  let obj: unknown;
  try {
    obj = JSON.parse(raw);
  } catch {
    throw new FrameParseError(`Invalid JSON: ${raw}`);
  }

  if (obj === null || typeof obj !== "object") {
    throw new FrameParseError(`Expected object, got ${typeof obj}`);
  }

  const frame = obj as Record<string, unknown>;

  if (!frame.type || typeof frame.type !== "string") {
    throw new FrameParseError(`Missing or invalid 'type' field`);
  }

    switch (frame.type) {
    case "registered":
      return frame as unknown as RegisteredFrame;
    case "error":
      // Could be RegisterErrorFrame or generic ErrorFrame
      return frame as unknown as RegisterErrorFrame | ErrorFrame;
    case "message":
      return frame as unknown as MessageFrame;
    case "ack":
      return frame as unknown as AckFrame;
    case "delivery_failed":
      return frame as unknown as DeliveryFailedFrame;
    case "pong":
      return frame as unknown as PongFrame;
    case "pairs_list":
      return frame as unknown as PairsListFrame;
    case "pair_request":
      return frame as unknown as PairRequestFrame;
    case "unpaired":
      return frame as unknown as UnpairedFrame;
    case "device_disconnected":
      return frame as unknown as DeviceDisconnectedFrame;
    default:
      // Unknown frame type — for forward compatibility, return as generic error-like object
      throw new FrameParseError(`Unknown frame type: ${frame.type}`);
  }
}

/**
 * Parse a raw JSON string, returning null for unknown frame types instead of throwing.
 */
export function parseFrameSafe(raw: string): IncomingFrame | null {
  try {
    return parseFrame(raw);
  } catch {
    return null;
  }
}
