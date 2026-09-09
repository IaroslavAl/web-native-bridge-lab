import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { BridgeClient } from "./bridgeClient";
import { MockNativeBoundary } from "./test/MockNativeBoundary";
import { TechnicalPanel } from "./TechnicalPanel";

const session = "0123456789abcdef0123456789abcdef";

function clientFor(handler: (message: Record<string, unknown>) => unknown): { client: BridgeClient; native: MockNativeBoundary } {
  const native = new MockNativeBoundary((message) =>
    message.type === "hello" ? { v: 1, type: "helloAck", session } : handler(message),
  );
  return { client: new BridgeClient(native), native };
}

describe("opt-in TechnicalPanel with explicitly mocked native boundary", () => {
  it("performs the document hello handshake on mount before engineering requests", async () => {
    const { client, native } = clientFor(() => { throw new Error("No request expected"); });
    render(<TechnicalPanel client={client} variant="A" />);
    await vi.waitFor(() => expect(native.decodedMessages()).toEqual([{ v: 1, type: "hello" }]));
  });

  it("retains scenario request construction and result summaries", async () => {
    const { client, native } = clientFor((message) => ({
      v: 1, type: "response", id: message.id, status: 200, headers: {},
      body: '{"items":[{"sku":"notebook","title":"Notebook"}],"total":1}',
    }));
    render(<TechnicalPanel client={client} variant="A" />);
    await userEvent.click(screen.getByTestId("lab.submit"));
    expect(await screen.findByTestId("lab.result")).toHaveTextContent("Notebook (notebook) — total 1");
    expect(native.decodedMessages()[1]).toMatchObject({ method: "GET", url: expect.stringContaining("/api/catalog?category=books") });
  });

  it("retains variant B quote as the default structured scenario", async () => {
    const { client, native } = clientFor((message) => ({
      v: 1, type: "response", id: message.id, status: 200, headers: {},
      body: '{"quote":{"sku":"notebook","quantity":2,"totalMinor":1200,"currency":"USD"}}',
    }));
    render(<TechnicalPanel client={client} variant="B" />);
    expect(screen.getByTestId("lab.scenario")).toHaveValue("quote");
    await userEvent.click(screen.getByTestId("lab.submit"));
    expect(await screen.findByTestId("lab.result")).toHaveTextContent("USD 1200 minor units");
    expect(native.decodedMessages()[1]).toMatchObject({ method: "POST", url: "http://127.0.0.1:8788/api/quote" });
  });

  it.each([
    ["HTTP error", "HTTP", 503, '{"error":{"code":"UNAVAILABLE","message":"Try later"}}'],
    ["Business error", "business", 200, '{"error":{"code":"OUT_OF_STOCK","message":"Not available"}}'],
    ["Malformed JSON", "JSON parse", 200, '{"broken":'],
  ])("retains the %s diagnostic category", async (buttonName, category, status, body) => {
    const { client } = clientFor((message) => ({ v: 1, type: "response", id: message.id, status, headers: {}, body }));
    render(<TechnicalPanel client={client} variant="A" />);
    await userEvent.click(screen.getByRole("button", { name: buttonName }));
    expect(await screen.findByTestId("lab.error")).toHaveTextContent(category);
  });

  it("keeps the fast result while cancelling only the slow request", async () => {
    let settleSlow: ((value: unknown) => void) | undefined;
    const { client, native } = clientFor((message) => {
      if (message.type === "cancel") {
        settleSlow?.({ v: 1, type: "error", id: message.id, code: "CANCELLED", message: "Cancelled" });
        return { v: 1, type: "cancelAck", id: message.id, cancelled: true };
      }
      if (String(message.url).includes("label=slow")) return new Promise((resolve) => { settleSlow = resolve; });
      return { v: 1, type: "response", id: message.id, status: 200, headers: {}, body: '{"label":"fast","delayedMs":10}' };
    });
    render(<TechnicalPanel client={client} variant="A" />);
    await userEvent.click(screen.getByRole("button", { name: "Run concurrent requests" }));
    expect(native.decodedMessages().find((message) => String(message.url).includes("label=slow")))
      .toMatchObject({ timeoutMs: 15000 });
    expect(await screen.findByText(/fast — 10 ms/)).toBeVisible();
    expect(screen.getByTestId("lab.loading")).toHaveTextContent("1 request");
    await userEvent.click(screen.getByTestId("lab.cancel"));
    expect(await screen.findByTestId("lab.error")).toHaveTextContent("transport CANCELLED");
    expect(screen.getByText(/fast — 10 ms/)).toBeVisible();
  });

  it("renders a hostile HTTP body literally without injected elements or side effects", async () => {
    const body = '<img src=x onerror="document.title=\'injected\'"> <script>alert(1)</script>';
    const { client } = clientFor((message) => ({ v: 1, type: "response", id: message.id, status: 503, headers: {}, body }));
    render(<TechnicalPanel client={client} variant="A" />);
    await userEvent.click(screen.getByRole("button", { name: "HTTP error" }));
    const panel = await screen.findByTestId("lab.error");
    expect(panel).toHaveTextContent(body);
    expect(panel.querySelector("img,script")).toBeNull();
    expect(document.title).not.toBe("injected");
  });

  it("shows bridge unavailable with no substitute network action", () => {
    render(<TechnicalPanel client={null} variant="B" startupError="Bridge unavailable: open in BridgeLab." />);
    expect(screen.getByTestId("lab.error")).toHaveTextContent("Bridge unavailable");
    expect(screen.getByTestId("lab.submit")).toBeDisabled();
  });
});
