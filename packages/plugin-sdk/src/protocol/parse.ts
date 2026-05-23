/**
 * Parse incoming JSON frames from Router.
 */

import { parse, ProtocolParseError } from "@openclaw/protocol";
import type { IncomingFrame } from "./types.js";

export { ProtocolParseError as FrameParseError };

export function parseFrame(raw: string): IncomingFrame {
  return parse(raw) as IncomingFrame;
}

export function parseFrameSafe(raw: string): IncomingFrame | null {
  try {
    return parseFrame(raw);
  } catch {
    return null;
  }
}
