/**
 * Logger interface used throughout the SDK.
 * Allows the consumer to inject their own logger or use the built-in console logger.
 */
export interface Logger {
    trace(msg: string): void;
    debug(msg: string): void;
    info(msg: string): void;
    warn(msg: string): void;
    error(msg: string): void;
}
/**
 * Creates a logger that prefixes all messages.
 */
export declare function createPrefixedLogger(prefix: string): Logger;
/**
 * No-op logger that discards all logs.
 */
export declare const noopLogger: Logger;
//# sourceMappingURL=logger.d.ts.map