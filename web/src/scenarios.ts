import type { BridgeRequestInput, BridgeResponse } from "./bridgeClient";
import { currencyMinorUnitExponent } from "./money";

export type ScenarioName = "catalog" | "quote";
export type InterpretationCategory = "HTTP" | "business" | "JSON parse";

export type ScenarioResult =
  | {
      kind: "catalog";
      summary: string;
      items: Array<{ sku: string; title: string }>;
      total: number;
    }
  | {
      kind: "quote";
      summary: string;
      quote: { sku: string; quantity: number; totalMinor: number; currency: string; minorUnitExponent: number };
    }
  | { kind: "diagnostic"; summary: string };

export class ResponseInterpretationError extends Error {
  constructor(
    readonly category: InterpretationCategory,
    message: string,
    readonly status?: number,
  ) {
    super(message);
    this.name = "ResponseInterpretationError";
  }
}

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

function parseJson(response: BridgeResponse): unknown {
  if (response.status < 200 || response.status >= 300) {
    throw new ResponseInterpretationError(
      "HTTP",
      `HTTP ${response.status}: ${response.body || "empty response"}`,
      response.status,
    );
  }
  try {
    return JSON.parse(response.body) as unknown;
  } catch {
    throw new ResponseInterpretationError("JSON parse", "Response body is not valid JSON.");
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function businessError(value: unknown): ResponseInterpretationError | undefined {
  if (!isRecord(value) || !isRecord(value.error)) return undefined;
  const code = typeof value.error.code === "string" ? value.error.code : "UNKNOWN";
  const message = typeof value.error.message === "string" ? value.error.message : "Business request failed";
  return new ResponseInterpretationError("business", `${code}: ${message}`);
}

function invalidBusinessShape(expected: string): never {
  throw new ResponseInterpretationError("business", `Unexpected ${expected} response shape.`);
}

export function interpretCatalog(response: BridgeResponse): ScenarioResult {
  const decoded = parseJson(response);
  const error = businessError(decoded);
  if (error) throw error;
  if (!isRecord(decoded) || !Array.isArray(decoded.items) || !Number.isInteger(decoded.total)) {
    return invalidBusinessShape("catalog");
  }
  const items = decoded.items.map((item) => {
    if (!isRecord(item) || typeof item.sku !== "string" || typeof item.title !== "string") {
      return invalidBusinessShape("catalog item");
    }
    return { sku: item.sku, title: item.title };
  });
  const itemSummary = items.length > 0
    ? items.map((item) => `${item.title} (${item.sku})`).join(", ")
    : "No items";
  return {
    kind: "catalog",
    summary: `${itemSummary} — total ${decoded.total as number}`,
    items,
    total: decoded.total as number,
  };
}

export function interpretQuote(response: BridgeResponse): ScenarioResult {
  const decoded = parseJson(response);
  const error = businessError(decoded);
  if (error) throw error;
  if (!isRecord(decoded) || !isRecord(decoded.quote)) return invalidBusinessShape("quote");
  const quote = decoded.quote;
  const minorUnitExponent = typeof quote.currency === "string"
    ? currencyMinorUnitExponent(quote.currency)
    : null;
  if (
    typeof quote.sku !== "string" ||
    !Number.isSafeInteger(quote.quantity) ||
    (quote.quantity as number) < 1 ||
    !Number.isSafeInteger(quote.totalMinor) ||
    (quote.totalMinor as number) < 0 ||
    typeof quote.currency !== "string" ||
    minorUnitExponent === null
  ) {
    return invalidBusinessShape("quote");
  }
  return {
    kind: "quote",
    summary: `${quote.sku} × ${quote.quantity as number} — ${quote.currency} ${quote.totalMinor as number} minor units`,
    quote: {
      sku: quote.sku,
      quantity: quote.quantity as number,
      totalMinor: quote.totalMinor as number,
      currency: quote.currency,
      minorUnitExponent,
    },
  };
}

export function interpretDelay(response: BridgeResponse): ScenarioResult {
  const decoded = parseJson(response);
  const error = businessError(decoded);
  if (error) throw error;
  if (!isRecord(decoded) || typeof decoded.label !== "string" || !Number.isInteger(decoded.delayedMs)) {
    return invalidBusinessShape("delay diagnostic");
  }
  return { kind: "diagnostic", summary: `${decoded.label} — ${decoded.delayedMs as number} ms` };
}

export function interpretBusinessFixture(response: BridgeResponse): ScenarioResult {
  const decoded = parseJson(response);
  const error = businessError(decoded);
  if (error) throw error;
  return invalidBusinessShape("business-error fixture");
}
