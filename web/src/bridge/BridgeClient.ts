import type { NativeBoundary } from "./WebKitNativeBoundary";
import {
  BridgeClientError,
  TransportError,
  parseCancelAck,
  parseHelloAck,
  parseRequestReply,
  rejectedNativeInvocation,
  type BridgeRequestInput,
  type BridgeResponse,
  type PendingBridgeRequest,
} from "./protocol";

const MAX_ID = 2_147_483_647;

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
      throw rejectedNativeInvocation();
    } finally {
      this.activeIds.delete(id);
    }
  }
}
