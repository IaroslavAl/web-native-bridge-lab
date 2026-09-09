import { describe, expect, it, vi } from "vitest";
import {
  WEB_HISTORY_KEY,
  clearDemoHistory,
  consumeDemoHistory,
  createLoadedIdentity,
  saveUpdateHistory,
  selectWebSurface,
} from "./webIdentity";

const aIdentity = { variant: "A" as const, entryPath: "/assets/index-a1b2c3.js" };

function memoryStorage(initial?: string) {
  let value = initial ?? null;
  return {
    getItem: vi.fn((key: string) => key === WEB_HISTORY_KEY ? value : null),
    setItem: vi.fn((key: string, next: string) => { if (key === WEB_HISTORY_KEY) value = next; }),
    removeItem: vi.fn((key: string) => { if (key === WEB_HISTORY_KEY) value = null; }),
  };
}

describe("loaded web identity", () => {
  it("accepts only an emitted asset entry path and keeps the compiled variant", () => {
    expect(createLoadedIdentity("A", "http://127.0.0.1:8787/assets/index-a1b2c3.js")).toEqual(aIdentity);
    expect(createLoadedIdentity("B", "http://127.0.0.1:8787/src/main.tsx")).toBeNull();
    expect(createLoadedIdentity("A", "not a URL")).toBeNull();
  });

  it("selects diagnostics only for one exact mode value", () => {
    expect(selectWebSurface("?mode=diagnostics")).toBe("diagnostics");
    expect(selectWebSurface("?mode=diagnostics&mode=diagnostics")).toBe("demo");
    expect(selectWebSurface("?mode=Diagnostics")).toBe("demo");
    expect(selectWebSurface("?mode=unknown")).toBe("demo");
    expect(selectWebSurface("")).toBe("demo");
  });
});

describe("bounded untrusted demo continuity", () => {
  it("round-trips the closed update record and consumes it once", () => {
    const storage = memoryStorage();
    expect(saveUpdateHistory(storage, aIdentity, true)).toBe(true);
    expect(consumeDemoHistory(storage)).toEqual({
      v: 1,
      previous: aIdentity,
      catalogSeen: true,
      updateRequested: true,
    });
    expect(storage.removeItem).toHaveBeenCalledWith(WEB_HISTORY_KEY);
    expect(consumeDemoHistory(storage)).toBeNull();
  });

  it.each([
    "not json",
    JSON.stringify({ v: 1, previous: { variant: "A", entryPath: `/assets/${"x".repeat(250)}.js` }, catalogSeen: true, updateRequested: true }),
    JSON.stringify({ v: 1, previous: { variant: "C", entryPath: "/assets/x.js" }, catalogSeen: true, updateRequested: true }),
    JSON.stringify({ v: 1, previous: aIdentity, catalogSeen: "yes", updateRequested: true }),
    JSON.stringify({ v: 1, previous: aIdentity, catalogSeen: true, updateRequested: true, capability: "quote" }),
  ])("rejects corrupt, oversized or open records without throwing", (raw) => {
    const storage = memoryStorage(raw);
    expect(consumeDemoHistory(storage)).toBeNull();
    expect(storage.removeItem).toHaveBeenCalledWith(WEB_HISTORY_KEY);
  });

  it("treats inaccessible storage as unavailable", () => {
    const storage = {
      getItem: vi.fn(() => { throw new Error("denied"); }),
      setItem: vi.fn(() => { throw new Error("denied"); }),
      removeItem: vi.fn(() => { throw new Error("denied"); }),
    };
    expect(saveUpdateHistory(storage, aIdentity, true)).toBe(false);
    expect(consumeDemoHistory(storage)).toBeNull();
  });

  it("diagnostics clears only the continuity key without reading history", () => {
    const storage = memoryStorage("opaque");
    clearDemoHistory(storage);
    expect(storage.removeItem).toHaveBeenCalledTimes(1);
    expect(storage.removeItem).toHaveBeenCalledWith(WEB_HISTORY_KEY);
    expect(storage.getItem).not.toHaveBeenCalled();
    expect(storage.setItem).not.toHaveBeenCalled();
  });
});
