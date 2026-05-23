/**
 * Serialize outgoing frames to JSON strings.
 */
import { serialize } from "@openclaw/protocol";
export function serializeFrame(frame) {
    return serialize(frame);
}
export function serializeRegister(frame) {
    return serializeFrame(frame);
}
export function serializeMessage(frame) {
    return serializeFrame(frame);
}
export function serializeAck(frame) {
    return serializeFrame(frame);
}
export function serializePing(frame) {
    return serializeFrame(frame);
}
export function serializePong(frame) {
    return serializeFrame(frame);
}
export function serializeListPairs(frame) {
    return serializeFrame(frame);
}
export function serializePairResponse(frame) {
    return serializeFrame(frame);
}
//# sourceMappingURL=serialize.js.map