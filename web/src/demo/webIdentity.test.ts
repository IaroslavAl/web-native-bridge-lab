import { describe, expect, it, vi } from "vitest";
import {
  MAX_SERIALIZED_HISTORY_LENGTH,
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
  it("fixes the serialized history limit at 512 UTF-16 code units", () => {
    expect(MAX_SERIALIZED_HISTORY_LENGTH).toBe(512);
  });

  it("bounds literal 512, 513 and 65,536 padded records before parsing", () => {
    const compact = JSON.stringify({ v: 1, previous: aIdentity, catalogSeen: true, updateRequested: true });
    expect(compact.length).toBeLessThan(512);
    const raw512 = compact + " ".repeat(512 - compact.length);
    const raw513 = compact + " ".repeat(513 - compact.length);
    const raw65536 = compact + " ".repeat(65_536 - compact.length);
    expect(raw512.length).toBe(512);
    expect(raw513.length).toBe(513);
    expect(raw65536.length).toBe(65_536);

    for (const [raw, accepted, parseCalls] of [
      [raw512, true, 1],
      [raw513, false, 0],
      [raw65536, false, 0],
    ] as const) {
      const order: string[] = [];
      let value: string | null = raw;
      const storage = {
        getItem: vi.fn(() => value),
        setItem: vi.fn((_key: string, next: string) => { value = next; }),
        removeItem: vi.fn(() => { order.push("remove"); value = null; }),
      };
      const originalParse = JSON.parse;
      const parse = vi.spyOn(JSON, "parse").mockImplementation((text: string) => {
        order.push("parse");
        return originalParse(text);
      });

      expect(consumeDemoHistory(storage) !== null).toBe(accepted);
      expect(storage.removeItem).toHaveBeenCalledTimes(1);
      expect(parse).toHaveBeenCalledTimes(parseCalls);
      expect(order).toEqual(parseCalls === 1 ? ["remove", "parse"] : ["remove"]);
      expect(consumeDemoHistory(storage)).toBeNull();
      parse.mockRestore();
    }
  });

  it("removes under-bound malformed JSON before one caught parse attempt", () => {
    const order: string[] = [];
    const originalParse = JSON.parse;
    const parse = vi.spyOn(JSON, "parse").mockImplementation((text: string) => {
      order.push("parse");
      return originalParse(text);
    });
    const storage = memoryStorage("{");
    storage.removeItem.mockImplementation(() => { order.push("remove"); });
    expect(consumeDemoHistory(storage)).toBeNull();
    expect(storage.removeItem).toHaveBeenCalledTimes(1);
    expect(parse).toHaveBeenCalledTimes(1);
    expect(order).toEqual(["remove", "parse"]);
    parse.mockRestore();
  });

  it("does not parse or claim deletion when removal throws after a successful get", () => {
    const compact = JSON.stringify({ v: 1, previous: aIdentity, catalogSeen: true, updateRequested: true });
    const raw512 = compact + " ".repeat(512 - compact.length);
    expect(raw512.length).toBe(512);
    const parse = vi.spyOn(JSON, "parse");
    const storage = {
      getItem: vi.fn(() => raw512),
      setItem: vi.fn(),
      removeItem: vi.fn(() => { throw new Error("denied"); }),
    };
    expect(consumeDemoHistory(storage)).toBeNull();
    expect(storage.getItem).toHaveBeenCalledTimes(1);
    expect(storage.removeItem).toHaveBeenCalledTimes(1);
    expect(parse).not.toHaveBeenCalled();
    parse.mockRestore();
  });

  it("does not attempt removal or parsing when storage get throws", () => {
    const parse = vi.spyOn(JSON, "parse");
    const storage = {
      getItem: vi.fn(() => { throw new Error("denied"); }),
      setItem: vi.fn(),
      removeItem: vi.fn(),
    };
    expect(consumeDemoHistory(storage)).toBeNull();
    expect(storage.removeItem).not.toHaveBeenCalled();
    expect(parse).not.toHaveBeenCalled();
    parse.mockRestore();
  });

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
