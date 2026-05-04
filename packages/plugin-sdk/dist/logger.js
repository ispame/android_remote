/**
 * Logger interface used throughout the SDK.
 * Allows the consumer to inject their own logger or use the built-in console logger.
 */
/**
 * Creates a logger that prefixes all messages.
 */
export function createPrefixedLogger(prefix) {
    return {
        trace: (msg) => console.debug(`[${prefix}] ${msg}`),
        debug: (msg) => console.debug(`[${prefix}] ${msg}`),
        info: (msg) => console.info(`[${prefix}] ${msg}`),
        warn: (msg) => console.warn(`[${prefix}] ${msg}`),
        error: (msg) => console.error(`[${prefix}] ${msg}`),
    };
}
/**
 * No-op logger that discards all logs.
 */
export const noopLogger = {
    trace: () => { },
    debug: () => { },
    info: () => { },
    warn: () => { },
    error: () => { },
};
//# sourceMappingURL=logger.js.map