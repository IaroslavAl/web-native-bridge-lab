import { describe, expect, it } from "vitest";
import {
  buildCatalogRequest,
  buildQuoteRequest,
  interpretCatalog,
  interpretQuote,
  ResponseInterpretationError,
  type InterpretationCategory,
} from "./scenarios";
import type { BridgeResponse } from "./bridgeClient";

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
    });
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
});
