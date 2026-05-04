/**
 * HTTP client for Plugin → Router callbacks.
 *
 * Used for:
 * - POST /api/callback/:requestId  (command result)
 * - POST /api/plugin/event         (event push)
 */
export interface HttpClientConfig {
    /** Base URL of the Router (e.g., https://boson-tech.top). */
    baseUrl: string;
    /** Plugin token for authentication. */
    token: string;
}
export interface CommandResultParams {
    requestId: string;
    success: boolean;
    result?: unknown;
    durationMs: number;
}
export interface EventPushParams {
    backendId: string;
    event: string;
    data: unknown;
}
export interface HttpClientError extends Error {
    statusCode?: number;
    code?: string;
}
/**
 * Simple HTTP client for callback/event push operations.
 */
export declare class HttpClient {
    private baseUrl;
    private token;
    constructor(config: HttpClientConfig);
    /**
     * Report command execution result to Router.
     *
     * POST /api/callback/:requestId
     * Body: { success, result, durationMs }
     */
    reportCommandResult(params: CommandResultParams): Promise<void>;
    /**
     * Push an event to Router (forwarded to paired App).
     *
     * POST /api/plugin/event
     * Body: { backend_id, event, data }
     */
    pushEvent(params: EventPushParams): Promise<void>;
    private post;
}
//# sourceMappingURL=http-client.d.ts.map