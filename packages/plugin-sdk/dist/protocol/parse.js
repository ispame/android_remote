/**
 * Parse incoming JSON frames from Router.
 */
/**
 * Error thrown when a frame cannot be parsed.
 */
export class FrameParseError extends Error {
    constructor(message) {
        super(message);
        this.name = "FrameParseError";
    }
}
/**
 * Parse a raw JSON string into an IncomingFrame.
 * Returns null if the frame type is unrecognized (for forward compatibility).
 */
export function parseFrame(raw) {
    let obj;
    try {
        obj = JSON.parse(raw);
    }
    catch {
        throw new FrameParseError(`Invalid JSON: ${raw}`);
    }
    if (obj === null || typeof obj !== "object") {
        throw new FrameParseError(`Expected object, got ${typeof obj}`);
    }
    const frame = obj;
    if (!frame.type || typeof frame.type !== "string") {
        throw new FrameParseError(`Missing or invalid 'type' field`);
    }
    switch (frame.type) {
        case "registered":
            return frame;
        case "error":
            // Could be RegisterErrorFrame or generic ErrorFrame
            return frame;
        case "message":
            return frame;
        case "ack":
            return frame;
        case "delivery_failed":
            return frame;
        case "pong":
            return frame;
        case "pairs_list":
            return frame;
        case "pair_request":
            return frame;
        case "unpaired":
            return frame;
        case "device_disconnected":
            return frame;
        default:
            // Unknown frame type — for forward compatibility, return as generic error-like object
            throw new FrameParseError(`Unknown frame type: ${frame.type}`);
    }
}
/**
 * Parse a raw JSON string, returning null for unknown frame types instead of throwing.
 */
export function parseFrameSafe(raw) {
    try {
        return parseFrame(raw);
    }
    catch {
        return null;
    }
}
//# sourceMappingURL=parse.js.map