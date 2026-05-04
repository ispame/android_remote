/**
 * Serialize outgoing frames to JSON strings.
 */
/**
 * Serialize any outgoing frame to a JSON string.
 * Throws if the frame type is unknown.
 */
export function serializeFrame(frame) {
    return JSON.stringify(frame);
}
/**
 * Serialize a register frame.
 */
export function serializeRegister(frame) {
    return JSON.stringify(frame);
}
/**
 * Serialize a message frame.
 */
export function serializeMessage(frame) {
    return JSON.stringify(frame);
}
/**
 * Serialize an ack frame.
 */
export function serializeAck(frame) {
    return JSON.stringify(frame);
}
/**
 * Serialize a ping frame.
 */
export function serializePing(frame) {
    return JSON.stringify(frame);
}
/**
 * Serialize a pong frame.
 */
export function serializePong(frame) {
    return JSON.stringify(frame);
}
/**
 * Serialize a list_pairs frame.
 */
export function serializeListPairs(frame) {
    return JSON.stringify(frame);
}
/**
 * Serialize a pair_response frame.
 */
export function serializePairResponse(frame) {
    return JSON.stringify(frame);
}
//# sourceMappingURL=serialize.js.map