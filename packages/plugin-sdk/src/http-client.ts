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

export interface AiChatMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

export interface AiChatParams {
  backendId: string;
  accountId: string;
  modelProfileId?: string;
  agentProfileId?: string;
  messages: AiChatMessage[];
}

export interface AiChatResponse {
  id: string;
  model_profile_id: string;
  message: { role: "assistant"; content: string };
  usage: {
    prompt_tokens?: number;
    completion_tokens?: number;
    total_tokens?: number;
  };
  billing: {
    charged_cents: number;
    usage_event_id: string | null;
  };
}

export interface HttpClientError extends Error {
  statusCode?: number;
  code?: string;
}

/**
 * Simple HTTP client for callback/event push operations.
 */
export class HttpClient {
  private baseUrl: string;
  private token: string;

  constructor(config: HttpClientConfig) {
    this.baseUrl = config.baseUrl.replace(/\/+$/, ""); // Strip trailing slashes
    this.token = config.token;
  }

  /**
   * Report command execution result to Router.
   *
   * POST /api/callback/:requestId
   * Body: { success, result, durationMs }
   */
  async reportCommandResult(params: CommandResultParams): Promise<void> {
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
  async pushEvent(params: EventPushParams): Promise<void> {
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
  async chat(params: AiChatParams): Promise<AiChatResponse> {
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
    return await response.json() as AiChatResponse;
  }

  private async post(url: string, body: unknown, extraHeaders: Record<string, string> = {}): Promise<Response> {
    let response: Response;

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
    } catch (networkError) {
      const err = new Error(
        `HTTP POST failed: ${networkError instanceof Error ? networkError.message : String(networkError)}`
      ) as HttpClientError;
      throw err;
    }

    if (!response.ok) {
      const responseError = await parseResponseError(response);
      const err = new Error(
        responseError.message || `HTTP POST ${url} returned ${response.status}: ${response.statusText}`
      ) as HttpClientError;
      err.statusCode = response.status;
      err.code = responseError.code;
      throw err;
    }

    return response;
  }
}

async function parseResponseError(response: Response): Promise<{ code?: string; message?: string }> {
  try {
    const body = await response.json() as {
      error?: { code?: unknown; message?: unknown };
      code?: unknown;
      message?: unknown;
    };
    const nested = body.error ?? {};
    return {
      code: stringOrUndefined(nested.code) ?? stringOrUndefined(body.code),
      message: stringOrUndefined(nested.message) ?? stringOrUndefined(body.message),
    };
  } catch {
    return {};
  }
}

function stringOrUndefined(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}
