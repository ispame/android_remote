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
    /**
     * Call Router LLM from a paired backend.
     *
     * POST /api/v2/backend/ai/chat
     */
    async chat(params) {
        const url = `${this.baseUrl}/api/v2/backend/ai/chat`;
        const body = {
            account_id: params.accountId,
            ...(params.modelProfileId !== undefined && { model_profile_id: params.modelProfileId }),
            ...(params.agentProfileId !== undefined && { agent_profile_id: params.agentProfileId }),
            messages: params.messages,
        };
        const response = await this.post(url, body, {
            "X-Boson-Backend-Id": params.backendId,
        });
        return await response.json();
    }
    async post(url, body, extraHeaders = {}) {
        let response;
        try {
            response = await fetch(url, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-Plugin-Token": this.token,
                    ...extraHeaders,
                },
                body: JSON.stringify(body),
            });
        }
        catch (networkError) {
            const err = new Error(`HTTP POST failed: ${networkError instanceof Error ? networkError.message : String(networkError)}`);
            throw err;
        }
        if (!response.ok) {
            const responseError = await parseResponseError(response);
            const err = new Error(responseError.message || `HTTP POST ${url} returned ${response.status}: ${response.statusText}`);
            err.statusCode = response.status;
            err.code = responseError.code;
            throw err;
        }
        return response;
    }
}
async function parseResponseError(response) {
    try {
        const body = await response.json();
        const nested = body.error ?? {};
        return {
            code: stringOrUndefined(nested.code) ?? stringOrUndefined(body.code),
            message: stringOrUndefined(nested.message) ?? stringOrUndefined(body.message),
        };
    }
    catch {
        return {};
    }
}
function stringOrUndefined(value) {
    return typeof value === "string" && value.length > 0 ? value : undefined;
}
//# sourceMappingURL=http-client.js.map