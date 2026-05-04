/**
 * Parse incoming JSON frames from Router.
 */
import type { IncomingFrame } from "./types.js";
/**
 * Error thrown when a frame cannot be parsed.
 */
export declare class FrameParseError extends Error {
    constructor(message: string);
}
/**
 * Parse a raw JSON string into an IncomingFrame.
 * Returns null if the frame type is unrecognized (for forward compatibility).
 */
export declare function parseFrame(raw: string): IncomingFrame;
/**
 * Parse a raw JSON string, returning null for unknown frame types instead of throwing.
 */
export declare function parseFrameSafe(raw: string): IncomingFrame | null;
//# sourceMappingURL=parse.d.ts.map