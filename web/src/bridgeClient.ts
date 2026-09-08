export type HttpMethod = "GET" | "POST";
export type AllowedRequestHeaders = Partial<
  Record<"accept" | "content-type" | "x-lab-tag", string>
>;

export interface BridgeRequestInput {
  method: HttpMethod;
  url: string;
  headers: AllowedRequestHeaders;
  body: string | null;
  timeoutMs?: number;
}

export interface BridgeResponse {
  v: 1;
  type: "response";
  id: number;
  status: number;
  headers: Partial<Record<"content-type" | "x-lab-tag", string>>;
  body: string;
}

export interface NativeBoundary {
  postMessage(serializedMessage: string): Promise<unknown>;
}

export interface PendingBridgeRequest {
  id: number;
  promise: Promise<BridgeResponse>;
  cancel(): Promise<boolean>;
}

export const TRANSPORT_CODES = [
  "ORIGIN_DENIED",
  "MESSAGE_TOO_LARGE",
  "UNSUPPORTED_VERSION",
  "INVALID_REQUEST",
  "URL_DENIED",
  "REQUEST_TOO_LARGE",
  "BUSY",
  "REDIRECT_DENIED",
  "RESPONSE_TOO_LARGE",
  "UNSUPPORTED_RESPONSE",
  "RESPONSE_ENCODING",
  "TIMEOUT",
  "CANCELLED",
  "NETWORK_ERROR",
] as const;

export type TransportCode = (typeof TRANSPORT_CODES)[number];

export class TransportError extends Error {
  readonly category = "transport";

  constructor(
    readonly code: TransportCode,
    message: string,
    readonly requestId: number,
  ) {
    super(message);
    this.name = "TransportError";
  }
}

export class BridgeClientError extends Error {
  readonly category: "bridge" | "protocol";

  constructor(
    readonly code: "BRIDGE_UNAVAILABLE" | "PROTOCOL_ERROR" | "ID_EXHAUSTED",
    message: string,
  ) {
    super(message);
    this.name = "BridgeClientError";
    this.category = code === "BRIDGE_UNAVAILABLE" ? "bridge" : "protocol";
  }
}

const MAX_ID = 2_147_483_647;
const SESSION_PATTERN = /^[0-9a-f]{32}$/;
const RESPONSE_STATUSES_EXCLUDED = new Set([301, 302, 303, 307, 308]);
const TRANSPORT_CODE_SET = new Set<string>(TRANSPORT_CODES);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, keys: string[]): boolean {
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  return actual.length === expected.length && actual.every((key, index) => key === expected[index]);
}

function protocolError(detail: string): BridgeClientError {
  return new BridgeClientError("PROTOCOL_ERROR", `Invalid native bridge reply: ${detail}`);
}

function parseHelloAck(value: unknown): string {
  if (
    !isRecord(value) ||
    !hasExactKeys(value, ["v", "type", "session"]) ||
    value.v !== 1 ||
    value.type !== "helloAck" ||
    typeof value.session !== "string" ||
    !SESSION_PATTERN.test(value.session)
  ) {
    throw protocolError("expected closed helloAck envelope");
  }
  return value.session;
}

function parseResponseHeaders(value: unknown): BridgeResponse["headers"] {
  if (!isRecord(value)) throw protocolError("headers is not an object");
  const keys = Object.keys(value);
  if (keys.some((key) => key !== "content-type" && key !== "x-lab-tag")) {
    throw protocolError("response contains an unexposed header");
  }
  if (
    keys.some((key) => {
      const headerValue = value[key];
      return (
        typeof headerValue !== "string" ||
        headerValue.length > 8192 ||
        !/^[ -~]*$/.test(headerValue)
      );
    })
  ) {
    throw protocolError("response header value is outside the printable bound");
  }
  const exposedBytes = new TextEncoder().encode(
    keys.map((key) => `${key}${value[key] as string}`).join(""),
  ).length;
  if (exposedBytes > 8192) {
    throw protocolError("combined exposed response headers exceed the byte bound");
  }
  return value as BridgeResponse["headers"];
}

function parseRequestReply(value: unknown, expectedId: number): BridgeResponse {
  if (!isRecord(value) || value.v !== 1 || typeof value.type !== "string") {
    throw protocolError("expected a v1 object");
  }

  if (value.type === "error") {
    if (
      !hasExactKeys(value, ["v", "type", "id", "code", "message"]) ||
      value.id !== expectedId ||
      typeof value.code !== "string" ||
      !TRANSPORT_CODE_SET.has(value.code) ||
      typeof value.message !== "string" ||
      value.message.length < 1 ||
      value.message.length > 256
    ) {
      throw protocolError("malformed or mismatched error envelope");
    }
    throw new TransportError(value.code as TransportCode, value.message, expectedId);
  }

  if (
    value.type !== "response" ||
    !hasExactKeys(value, ["v", "type", "id", "status", "headers", "body"]) ||
    value.id !== expectedId ||
    !Number.isInteger(value.status) ||
    (value.status as number) < 100 ||
    (value.status as number) > 599 ||
    RESPONSE_STATUSES_EXCLUDED.has(value.status as number) ||
    typeof value.body !== "string"
  ) {
    throw protocolError("malformed or mismatched response envelope");
  }

  return {
    v: 1,
    type: "response",
    id: expectedId,
    status: value.status as number,
    headers: parseResponseHeaders(value.headers),
    body: value.body,
  };
}

function parseCancelAck(value: unknown, expectedId: number): boolean {
  if (
    !isRecord(value) ||
    !hasExactKeys(value, ["v", "type", "id", "cancelled"]) ||
    value.v !== 1 ||
    value.type !== "cancelAck" ||
    value.id !== expectedId ||
    typeof value.cancelled !== "boolean"
  ) {
    throw protocolError("malformed or mismatched cancelAck envelope");
  }
  return value.cancelled;
}

export class BridgeClient {
  private nextId = 1;
  private sessionPromise: Promise<string> | undefined;
  private readonly activeIds = new Set<number>();

  constructor(private readonly native: NativeBoundary) {}

  async connect(): Promise<void> {
    await this.getSession();
  }

  request(input: BridgeRequestInput): PendingBridgeRequest {
    if (this.nextId > MAX_ID) {
      throw new BridgeClientError("ID_EXHAUSTED", "Request id space exhausted; reload the page.");
    }

    const id = this.nextId++;
    this.activeIds.add(id);
    const promise = this.execute(id, input);
    return {
      id,
      promise,
      cancel: () => this.cancel(id),
    };
  }

  async cancel(id: number): Promise<boolean> {
    if (!this.activeIds.has(id)) return false;
    const session = await this.getSession();
    const reply = await this.native.postMessage(JSON.stringify({ v: 1, type: "cancel", session, id }));
    return parseCancelAck(reply, id);
  }

  attachPageLifecycle(target: Pick<Window, "addEventListener" | "removeEventListener">): () => void {
    const onPageHide = () => {
      for (const id of this.activeIds) void this.cancel(id).catch(() => undefined);
      this.sessionPromise = undefined;
    };
    target.addEventListener("pagehide", onPageHide);
    return () => target.removeEventListener("pagehide", onPageHide);
  }

  private getSession(): Promise<string> {
    if (!this.sessionPromise) {
      this.sessionPromise = this.native
        .postMessage(JSON.stringify({ v: 1, type: "hello" }))
        .then(parseHelloAck);
    }
    return this.sessionPromise;
  }

  private async execute(id: number, input: BridgeRequestInput): Promise<BridgeResponse> {
    try {
      const session = await this.getSession();
      const reply = await this.native.postMessage(
        JSON.stringify({
          v: 1,
          type: "request",
          session,
          id,
          method: input.method,
          url: input.url,
          headers: input.headers,
          body: input.body,
          timeoutMs: input.timeoutMs ?? 5000,
        }),
      );
      return parseRequestReply(reply, id);
    } catch (error) {
      if (error instanceof TransportError || error instanceof BridgeClientError) throw error;
      throw protocolError("native invocation rejected");
    } finally {
      this.activeIds.delete(id);
    }
  }
}

export function createWebKitNativeBoundary(root: unknown = globalThis): NativeBoundary {
  const candidate = root as {
    webkit?: { messageHandlers?: { nativeHTTP?: { postMessage?: (message: string) => unknown } } };
  };
  const postMessage = candidate.webkit?.messageHandlers?.nativeHTTP?.postMessage;
  if (typeof postMessage !== "function") {
    throw new BridgeClientError(
      "BRIDGE_UNAVAILABLE",
      "Bridge unavailable: open this page in BridgeLab.",
    );
  }
  return {
    postMessage: (message) => Promise.resolve(postMessage.call(candidate.webkit?.messageHandlers?.nativeHTTP, message)),
  };
}
