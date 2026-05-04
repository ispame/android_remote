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

  private async post(url: string, body: unknown): Promise<void> {
    let response: Response;

    try {
      response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Plugin-Token": this.token,
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
      const err = new Error(
        `HTTP POST ${url} returned ${response.status}: ${response.statusText}`
      ) as HttpClientError;
      err.statusCode = response.status;
      throw err;
    }
  }
}
