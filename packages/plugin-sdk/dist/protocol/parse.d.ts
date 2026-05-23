/**
 * Parse incoming JSON frames from Router.
 */
import { ProtocolParseError } from "@openclaw/protocol";
import type { IncomingFrame } from "./types.js";
export { ProtocolParseError as FrameParseError };
export declare function parseFrame(raw: string): IncomingFrame;
export declare function parseFrameSafe(raw: string): IncomingFrame | null;
//# sourceMappingURL=parse.d.ts.map