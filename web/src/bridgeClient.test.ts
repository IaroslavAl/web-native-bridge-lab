import { describe, expect, it, vi } from "vitest";
import {
  BridgeClient,
  BridgeClientError,
  TransportError,
  createWebKitNativeBoundary,
  type BridgeResponse,
} from "./bridgeClient";
import { MockNativeBoundary } from "./test/MockNativeBoundary";

const session = "0123456789abcdef0123456789abcdef";

function response(id: number, body: string): BridgeResponse {
  return { v: 1, type: "response", id, status: 200, headers: { "content-type": "application/json" }, body };
}

describe("BridgeClient with explicitly mocked native boundary", () => {
  it("performs one hello and correlates out-of-order concurrent replies", async () => {
    const resolvers = new Map<number, (value: unknown) => void>();
    const native = new MockNativeBoundary((message) => {
      if (message.type === "hello") return { v: 1, type: "helloAck", session };
      return new Promise((resolve) => resolvers.set(message.id as number, resolve));
    });
    const client = new BridgeClient(native);

    const first = client.request({
      method: "GET",
      url: "http://127.0.0.1:8788/api/catalog?category=books",
      headers: { accept: "application/json", "x-lab-tag": "scenario-a" },
      body: null,
    });
    const second = client.request({
      method: "POST",
      url: "http://127.0.0.1:8788/api/quote",
      headers: { accept: "application/json", "content-type": "application/json", "x-lab-tag": "scenario-b" },
      body: JSON.stringify({ sku: "notebook", quantity: 2 }),
    });

    await vi.waitFor(() => expect(native.messages).toHaveLength(3));
    resolvers.get(second.id)?.(response(second.id, "{\"quote\":{\"totalMinor\":1200}}"));
    resolvers.get(first.id)?.(response(first.id, "{\"items\":[],\"total\":0}"));

    await expect(second.promise).resolves.toMatchObject({ id: second.id, body: expect.stringContaining("1200") });
    await expect(first.promise).resolves.toMatchObject({ id: first.id, body: expect.stringContaining("items") });
    const [hello, requestOne, requestTwo] = native.decodedMessages();
    expect(hello).toEqual({ v: 1, type: "hello" });
    expect(requestOne).toMatchObject({ v: 1, type: "request", session, id: 1, timeoutMs: 5000 });
    expect(requestTwo).toMatchObject({ v: 1, type: "request", session, id: 2, method: "POST" });
  });

  it("rejects a mismatched or malformed native reply as a local protocol error", async () => {
    const native = new MockNativeBoundary((message) =>
      message.type === "hello"
        ? { v: 1, type: "helloAck", session }
        : response((message.id as number) + 1, "{}"),
    );
    const pending = new BridgeClient(native).request({
      method: "GET",
      url: "http://127.0.0.1:8788/api/catalog",
      headers: {},
      body: null,
    });

    await expect(pending.promise).rejects.toMatchObject({ code: "PROTOCOL_ERROR" });
  });

  it("rejects response headers outside the closed printable reply contract", async () => {
    const native = new MockNativeBoundary((message) =>
      message.type === "hello"
        ? { v: 1, type: "helloAck", session }
        : { ...response(message.id as number, "{}"), headers: { "x-lab-tag": "bad\nvalue" } },
    );
    const pending = new BridgeClient(native).request({
      method: "GET",
      url: "http://127.0.0.1:8788/api/catalog",
      headers: {},
      body: null,
    });

    await expect(pending.promise).rejects.toMatchObject({ code: "PROTOCOL_ERROR" });
  });

  it("maps native timeout and cancellation errors without a JavaScript deadline", async () => {
    const native = new MockNativeBoundary((message) => {
      if (message.type === "hello") return { v: 1, type: "helloAck", session };
      return { v: 1, type: "error", id: message.id, code: "TIMEOUT", message: "Native request deadline exceeded" };
    });
    const pending = new BridgeClient(native).request({
      method: "GET",
      url: "http://127.0.0.1:8788/fixtures/delay?ms=1000&label=slow",
      headers: {},
      body: null,
      timeoutMs: 50,
    });

    await expect(pending.promise).rejects.toBeInstanceOf(TransportError);
    await expect(pending.promise).rejects.toMatchObject({ code: "TIMEOUT" });
    expect(native.decodedMessages()[1]).toMatchObject({ timeoutMs: 50 });
  });

  it("sends cancel with the correlated id and session", async () => {
    let settleRequest: ((value: unknown) => void) | undefined;
    const native = new MockNativeBoundary((message) => {
      if (message.type === "hello") return { v: 1, type: "helloAck", session };
      if (message.type === "cancel") {
        settleRequest?.({ v: 1, type: "error", id: message.id, code: "CANCELLED", message: "Cancelled" });
        return { v: 1, type: "cancelAck", id: message.id, cancelled: true };
      }
      return new Promise((resolve) => { settleRequest = resolve; });
    });
    const pending = new BridgeClient(native).request({
      method: "GET",
      url: "http://127.0.0.1:8788/fixtures/delay?ms=1000&label=slow",
      headers: {},
      body: null,
    });

    await vi.waitFor(() => expect(native.messages).toHaveLength(2));
    await expect(pending.cancel()).resolves.toBe(true);
    await expect(pending.promise).rejects.toMatchObject({ code: "CANCELLED" });
    expect(native.decodedMessages()[2]).toEqual({ v: 1, type: "cancel", session, id: pending.id });
  });

  it("best-effort cancels every active request on pagehide", async () => {
    const requestResolvers = new Map<number, (value: unknown) => void>();
    const native = new MockNativeBoundary((message) => {
      if (message.type === "hello") return { v: 1, type: "helloAck", session };
      if (message.type === "cancel") {
        requestResolvers.get(message.id as number)?.({
          v: 1,
          type: "error",
          id: message.id,
          code: "CANCELLED",
          message: "Document hidden",
        });
        return { v: 1, type: "cancelAck", id: message.id, cancelled: true };
      }
      return new Promise((resolve) => requestResolvers.set(message.id as number, resolve));
    });
    const client = new BridgeClient(native);
    const detach = client.attachPageLifecycle(window);
    const first = client.request({ method: "GET", url: "http://127.0.0.1:8788/one", headers: {}, body: null });
    const second = client.request({ method: "GET", url: "http://127.0.0.1:8788/two", headers: {}, body: null });
    void first.promise.catch(() => undefined);
    void second.promise.catch(() => undefined);
    await vi.waitFor(() => expect(native.messages).toHaveLength(3));

    window.dispatchEvent(new Event("pagehide"));

    await vi.waitFor(() => {
      const cancels = native.decodedMessages().filter((message) => message.type === "cancel");
      expect(cancels.map((message) => message.id).sort()).toEqual([first.id, second.id]);
    });
    detach();
  });

  it("fails immediately when WebKit is unavailable and never calls fetch", () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    expect(() => createWebKitNativeBoundary({})).toThrowError(
      expect.objectContaining<Partial<BridgeClientError>>({ code: "BRIDGE_UNAVAILABLE" }),
    );
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});
