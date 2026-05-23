/**
 * Parse incoming JSON frames from Router.
 */
import { parse, ProtocolParseError } from "@openclaw/protocol";
export { ProtocolParseError as FrameParseError };
export function parseFrame(raw) {
    return parse(raw);
}
export function parseFrameSafe(raw) {
    try {
        return parseFrame(raw);
    }
    catch {
        return null;
    }
}
//# sourceMappingURL=parse.js.map