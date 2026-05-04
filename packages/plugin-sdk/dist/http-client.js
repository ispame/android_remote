/**
 * HTTP client for Plugin → Router callbacks.
 *
 * Used for:
 * - POST /api/callback/:requestId  (command result)
 * - POST /api/plugin/event         (event push)
 */
/**
 * Simple HTTP client for callback/event push operations.
 */
export class HttpClient {
    baseUrl;
    token;
    constructor(config) {
        this.baseUrl = config.baseUrl.replace(/\/+$/, ""); // Strip trailing slashes
        this.token = config.token;
    }
    /**
     * Report command execution result to Router.
     *
     * POST /api/callback/:requestId
     * Body: { success, result, durationMs }
     */
    async reportCommandResult(params) {
        const url = `${this.baseUrl}/api/callback/${params.requestId}`;
        const body = {
            success: params.success,
            ...(params.result !== undefined && { result: params.result }),
            durationMs: params.durationMs,
        };
        await this.post(url, body);
    }
    /**
     * Push an event to Router (forwarded to paired App).
     *
     * POST /api/plugin/event
     * Body: { backend_id, event, data }
     */
    async pushEvent(params) {
        const url = `${this.baseUrl}/api/plugin/event`;
        const body = {
            backend_id: params.backendId,
            event: params.event,
            data: params.data,
        };
        await this.post(url, body);
    }
    async post(url, body) {
        let response;
        try {
            response = await fetch(url, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-Plugin-Token": this.token,
                },
                body: JSON.stringify(body),
            });
        }
        catch (networkError) {
            const err = new Error(`HTTP POST failed: ${networkError instanceof Error ? networkError.message : String(networkError)}`);
            throw err;
        }
        if (!response.ok) {
            const err = new Error(`HTTP POST ${url} returned ${response.status}: ${response.statusText}`);
            err.statusCode = response.status;
            throw err;
        }
    }
}
//# sourceMappingURL=http-client.js.map