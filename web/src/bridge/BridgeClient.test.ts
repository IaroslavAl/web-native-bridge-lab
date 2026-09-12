import { describe, expect, it, vi } from "vitest";
import {
  BridgeClient,
} from "./BridgeClient";
import { BridgeClientError, TransportError, type BridgeResponse } from "./protocol";
import { createWebKitNativeBoundary } from "./WebKitNativeBoundary";
import { MockNativeBoundary } from "../test/MockNativeBoundary";

const session = "0123456789abcdef0123456789abcdef";
const MAX_RESPONSE_BODY_BYTES = 1_048_576;

function response(id: number, body: string): BridgeResponse {
  return { v: 1, type: "response", id, status: 200, headers: { "content-type": "application/json" }, body };
}

function requestWithResponseBody(body: string) {
  const native = new MockNativeBoundary((message) =>
    message.type === "hello"
      ? { v: 1, type: "helloAck", session }
      : response(message.id as number, body),
  );
  return new BridgeClient(native).request({
    method: "GET",
    url: "http://127.0.0.1:8788/api/catalog",
    headers: {},
    body: null,
  }).promise;
}

describe("BridgeClient with explicitly mocked native boundary", () => {
  it("accepts the last id and fails closed without wrapping or another native call", async () => {
    const native = new MockNativeBoundary((message) => message.type === "hello"
      ? { v: 1, type: "helloAck", session } : response(message.id as number, "{}"));
    const client = new BridgeClient(native);
    // Explicit deterministic allocator seam; do not make two billion requests.
    Reflect.set(client, "nextId", 2_147_483_647);
    const input = { method: "GET" as const, url: "http://127.0.0.1:8788/last", headers: {}, body: null };
    const last = client.request(input);
    await expect(last.promise).resolves.toMatchObject({ id: 2_147_483_647 });
    expect(() => client.request(input)).toThrowError(expect.objectContaining({ code: "ID_EXHAUSTED" }));
    expect(native.messages).toHaveLength(2);
    await expect(last.cancel()).resolves.toBe(false);
    expect(native.messages).toHaveLength(2);
  });

  it("rejects malformed hello and cancel acknowledgements without accepting success", async () => {
    const input = { method: "GET" as const, url: "http://127.0.0.1:8788/test", headers: {}, body: null };
    const badHello = new MockNativeBoundary(() => ({ v: 1, type: "helloAck", session: "bad" }));
    await expect(new BridgeClient(badHello).request(input).promise).rejects.toMatchObject({ code: "PROTOCOL_ERROR" });
    expect(badHello.messages).toHaveLength(1);
    let settle: ((reply: unknown) => void) | undefined;
    const native = new MockNativeBoundary((message) => {
      if (message.type === "hello") return { v: 1, type: "helloAck", session };
      if (message.type === "cancel") return { v: 1, type: "cancelAck", id: message.id, cancelled: "true" };
      return new Promise((resolve) => { settle = resolve; });
    });
    const request = new BridgeClient(native).request(input);
    await vi.waitFor(() => expect(native.messages).toHaveLength(2));
    await expect(request.cancel()).rejects.toMatchObject({ code: "PROTOCOL_ERROR" });
    settle?.(response(request.id, "{}"));
    await expect(request.promise).resolves.toMatchObject({ id: request.id });
  });

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

  it("accepts a response body at the inclusive 1048576-byte boundary", async () => {
    const reply = await requestWithResponseBody("a".repeat(MAX_RESPONSE_BODY_BYTES));

    expect(new TextEncoder().encode(reply.body)).toHaveLength(MAX_RESPONSE_BODY_BYTES);
  });

  it("rejects a response body one byte over the 1048576-byte boundary", async () => {
    await expect(
      requestWithResponseBody("a".repeat(MAX_RESPONSE_BODY_BYTES + 1)),
    ).rejects.toMatchObject({ code: "PROTOCOL_ERROR" });
  });

  it("measures the response body bound in UTF-8 bytes rather than JavaScript characters", async () => {
    const body = `${"a".repeat(MAX_RESPONSE_BODY_BYTES - 1)}é`;
    expect(body).toHaveLength(MAX_RESPONSE_BODY_BYTES);
    expect(new TextEncoder().encode(body)).toHaveLength(MAX_RESPONSE_BODY_BYTES + 1);

    await expect(requestWithResponseBody(body)).rejects.toMatchObject({ code: "PROTOCOL_ERROR" });
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
