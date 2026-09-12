import { describe, expect, it } from "vitest";
import {
  buildCatalogRequest,
  buildQuoteRequest,
} from "./requestDefinitions";
import {
  interpretCatalog,
  interpretQuote,
  ResponseInterpretationError,
  type InterpretationCategory,
} from "./responseInterpreters";
import type { BridgeResponse } from "../bridge/protocol";

const ok = (body: string) => ({ v: 1 as const, type: "response" as const, id: 1, status: 200, headers: {}, body });

describe("web-owned scenarios", () => {
  it("constructs the catalog URL/query/headers and parses its list shape", () => {
    expect(buildCatalogRequest("books")).toEqual({
      method: "GET",
      url: "http://127.0.0.1:8788/api/catalog?category=books",
      headers: { accept: "application/json", "x-lab-tag": "scenario-a" },
      body: null,
    });
    expect(interpretCatalog(ok('{"items":[{"sku":"notebook","title":"Notebook"}],"total":1}'))).toEqual({
      kind: "catalog",
      summary: "Notebook (notebook) — total 1",
      items: [{ sku: "notebook", title: "Notebook" }],
      total: 1,
    });
  });

  it("constructs quote POST body and parses its distinct nested shape", () => {
    expect(buildQuoteRequest("notebook", 2)).toEqual({
      method: "POST",
      url: "http://127.0.0.1:8788/api/quote",
      headers: { accept: "application/json", "content-type": "application/json", "x-lab-tag": "scenario-b" },
      body: '{"sku":"notebook","quantity":2}',
    });
    expect(interpretQuote(ok('{"quote":{"sku":"notebook","quantity":2,"totalMinor":1200,"currency":"USD"}}'))).toEqual({
      kind: "quote",
      summary: "notebook × 2 — USD 1200 minor units",
      quote: { sku: "notebook", quantity: 2, totalMinor: 1200, currency: "USD", minorUnitExponent: 2 },
    });
  });

  it.each([
    '{"quote":{"sku":"notebook","quantity":2,"totalMinor":-1,"currency":"USD"}}',
    '{"quote":{"sku":"notebook","quantity":2,"totalMinor":1200,"currency":"usd"}}',
    '{"quote":{"sku":"notebook","quantity":2,"totalMinor":1200,"currency":"ZZZ"}}',
    '{"quote":{"sku":"notebook","quantity":0,"totalMinor":1200,"currency":"USD"}}',
  ])("rejects malformed money or quantity instead of creating a receipt", (body) => {
    expect(() => interpretQuote(ok(body))).toThrowError(
      expect.objectContaining({ category: "invalid success shape" }),
    );
  });

  it.each<[InterpretationCategory, BridgeResponse]>([
    ["HTTP", { ...ok('{"error":{"code":"UNAVAILABLE","message":"Try later"}}'), status: 503 }],
    ["business", ok('{"error":{"code":"OUT_OF_STOCK","message":"Not available"}}')],
    ["JSON parse", ok('{"broken":')],
  ])("classifies %s failures in web", (category, bridgeResponse) => {
    expect(() => interpretCatalog(bridgeResponse)).toThrowError(
      expect.objectContaining<Partial<ResponseInterpretationError>>({ category }),
    );
  });

  it("keeps an exact misleadingly named server envelope as business diagnostic data", () => {
    expect(() => interpretQuote(ok('{"error":{"code":"UnexpectedInventory","message":"Inventory changed"}}')))
      .toThrowError(expect.objectContaining<Partial<ResponseInterpretationError>>({
        category: "business",
        message: "UnexpectedInventory: Inventory changed",
      }));
  });

  it.each([
    '{"error":{}}',
    '{"error":{"code":"OUT_OF_STOCK"}}',
    '{"error":{"code":7,"message":"Unavailable"}}',
    '{"error":{"code":"","message":"Unavailable"}}',
    '{"error":{"code":"OUT_OF_STOCK","message":"   "}}',
    '{"error":{"code":"OUT_OF_STOCK","message":"Unavailable","retry":true}}',
    '{"error":{"code":"OUT_OF_STOCK","message":"Unavailable"},"quote":{"sku":"notebook","quantity":2,"totalMinor":1200,"currency":"USD"}}',
  ])("rejects malformed or open own-error envelope as invalid success shape: %s", (body) => {
    expect(() => interpretQuote(ok(body))).toThrowError(
      expect.objectContaining({ category: "invalid success shape" }),
    );
  });

  it.each([
    [interpretCatalog, '{"items":[{"sku":"notebook"}],"total":1}'],
    [interpretCatalog, '{"items":"not-a-list","total":1}'],
    [interpretQuote, '{"quote":{"sku":"notebook","quantity":2,"totalMinor":"1200","currency":"USD"}}'],
  ])("classifies endpoint success-shape failures independently from business rejection", (interpret, body) => {
    expect(() => interpret(ok(body))).toThrowError(
      expect.objectContaining({ category: "invalid success shape" }),
    );
  });
});
