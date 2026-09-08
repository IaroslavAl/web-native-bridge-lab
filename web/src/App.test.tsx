import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { App } from "./App";
import { BridgeClient } from "./bridgeClient";
import { MockNativeBoundary } from "./test/MockNativeBoundary";

const session = "0123456789abcdef0123456789abcdef";

function clientFor(handler: (message: Record<string, unknown>) => unknown): { client: BridgeClient; native: MockNativeBoundary } {
  const native = new MockNativeBoundary((message) =>
    message.type === "hello" ? { v: 1, type: "helloAck", session } : handler(message),
  );
  return { client: new BridgeClient(native), native };
}

describe("App with explicitly mocked native boundary", () => {
  it("performs the document hello handshake on mount before user requests", async () => {
    const { client, native } = clientFor(() => {
      throw new Error("No request expected");
    });

    render(<App client={client} variant="A" />);

    await vi.waitFor(() => expect(native.decodedMessages()).toEqual([{ v: 1, type: "hello" }]));
  });

  it("variant A submits catalog and renders list business data", async () => {
    const { client, native } = clientFor((message) => ({
      v: 1,
      type: "response",
      id: message.id,
      status: 200,
      headers: { "content-type": "application/json" },
      body: '{"items":[{"sku":"notebook","title":"Notebook"}],"total":1}',
    }));
    render(<App client={client} variant="A" />);

    expect(screen.getByTestId("lab.variant")).toHaveTextContent("Variant A");
    await userEvent.click(screen.getByTestId("lab.submit"));

    expect(await screen.findByTestId("lab.result")).toHaveTextContent("Notebook");
    expect(native.decodedMessages()[1]).toMatchObject({ method: "GET", url: expect.stringContaining("/api/catalog?category=books") });
  });

  it("variant B defaults to quote, builds POST in web, and renders nested quote", async () => {
    const { client, native } = clientFor((message) => ({
      v: 1,
      type: "response",
      id: message.id,
      status: 200,
      headers: { "content-type": "application/json" },
      body: '{"quote":{"sku":"notebook","quantity":2,"totalMinor":1200,"currency":"USD"}}',
    }));
    render(<App client={client} variant="B" />);

    expect(screen.getByTestId("lab.scenario")).toHaveValue("quote");
    await userEvent.click(screen.getByTestId("lab.submit"));

    expect(await screen.findByTestId("lab.result")).toHaveTextContent("USD 1200 minor units");
    expect(native.decodedMessages()[1]).toMatchObject({ method: "POST", url: "http://127.0.0.1:8788/api/quote" });
  });

  it.each([
    ["HTTP error", "HTTP", 503, '{"error":{"code":"UNAVAILABLE","message":"Try later"}}'],
    ["Business error", "business", 200, '{"error":{"code":"OUT_OF_STOCK","message":"Not available"}}'],
    ["Malformed JSON", "JSON parse", 200, '{"broken":'],
  ])("renders the %s category as web-owned UI", async (buttonName, category, status, body) => {
    const { client } = clientFor((message) => ({
      v: 1,
      type: "response",
      id: message.id,
      status,
      headers: { "content-type": "application/json" },
      body,
    }));
    render(<App client={client} variant="A" />);

    await userEvent.click(screen.getByRole("button", { name: buttonName }));

    expect(await screen.findByTestId("lab.error")).toHaveTextContent(category);
  });

  it("keeps fast and slow requests correlated and cancels only the slow request", async () => {
    let settleSlow: ((value: unknown) => void) | undefined;
    const { client } = clientFor((message) => {
      if (message.type === "cancel") {
        settleSlow?.({ v: 1, type: "error", id: message.id, code: "CANCELLED", message: "Cancelled" });
        return { v: 1, type: "cancelAck", id: message.id, cancelled: true };
      }
      const url = message.url as string;
      if (url.includes("label=slow")) return new Promise((resolve) => { settleSlow = resolve; });
      return {
        v: 1,
        type: "response",
        id: message.id,
        status: 200,
        headers: { "content-type": "application/json" },
        body: '{"label":"fast","delayedMs":10}',
      };
    });
    render(<App client={client} variant="A" />);

    await userEvent.click(screen.getByRole("button", { name: "Run concurrent requests" }));
    expect(await screen.findByText(/fast — 10 ms/)).toBeVisible();
    expect(screen.getByTestId("lab.loading")).toHaveTextContent("1 request");
    await userEvent.click(screen.getByTestId("lab.cancel"));
    expect(await screen.findByTestId("lab.error")).toHaveTextContent("transport CANCELLED");
    expect(screen.getByText(/fast — 10 ms/)).toBeVisible();
  });

  it("shows bridge unavailable without a substitute network path", () => {
    render(<App client={null} variant="A" startupError="Bridge unavailable: open this page in BridgeLab." />);
    expect(screen.getByTestId("lab.error")).toHaveTextContent("Bridge unavailable");
    expect(screen.getByTestId("lab.submit")).toBeDisabled();
  });
});
