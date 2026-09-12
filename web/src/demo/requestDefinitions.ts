import type { BridgeRequestInput } from "../bridge/protocol";

const API_BASE = "http://127.0.0.1:8788";

export function buildCatalogRequest(category: string): BridgeRequestInput {
  const url = new URL("/api/catalog", API_BASE);
  url.searchParams.set("category", category);
  return {
    method: "GET",
    url: url.toString(),
    headers: { accept: "application/json", "x-lab-tag": "scenario-a" },
    body: null,
  };
}

export function buildQuoteRequest(sku: string, quantity: number): BridgeRequestInput {
  return {
    method: "POST",
    url: new URL("/api/quote", API_BASE).toString(),
    headers: {
      accept: "application/json",
      "content-type": "application/json",
      "x-lab-tag": "scenario-b",
    },
    body: JSON.stringify({ sku, quantity }),
  };
}

export function buildFixtureRequest(
  path: string,
  timeoutMs = 5000,
  tag = "diagnostic",
): BridgeRequestInput {
  return {
    method: "GET",
    url: new URL(path, API_BASE).toString(),
    headers: { accept: "application/json", "x-lab-tag": tag },
    body: null,
    timeoutMs,
  };
}
