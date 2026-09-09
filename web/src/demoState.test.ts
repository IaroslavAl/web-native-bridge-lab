import { describe, expect, it } from "vitest";
import { classifyLoadedDemo } from "./demoState";
import type { DemoHistoryRecord, WebIdentity } from "./webIdentity";

const identity = (variant: "A" | "B", entryPath: string): WebIdentity => ({ variant, entryPath });
const history = (previous: WebIdentity, catalogSeen = true): DemoHistoryRecord => ({
  v: 1,
  previous,
  catalogSeen,
  updateRequested: true,
});

describe("loaded demo classification", () => {
  it("keeps A catalog-only after a same-identity reload", () => {
    expect(classifyLoadedDemo(identity("A", "/assets/a.js"), history(identity("A", "/assets/a.js"))))
      .toEqual({ capability: "catalog", update: "unchanged", observedCatalog: true });
  });

  it("does not unlock quote when a changed entry is still A", () => {
    expect(classifyLoadedDemo(identity("A", "/assets/a-new.js"), history(identity("A", "/assets/a.js"))))
      .toEqual({ capability: "catalog", update: "changed-a", observedCatalog: true });
  });

  it("attributes an A to B transition only to valid observed A history", () => {
    expect(classifyLoadedDemo(identity("B", "/assets/b.js"), history(identity("A", "/assets/a.js"))))
      .toEqual({ capability: "quote", update: "changed-to-b", observedCatalog: true });
    expect(classifyLoadedDemo(identity("B", "/assets/b.js"), null))
      .toEqual({ capability: "quote", update: "none", observedCatalog: false });
    expect(classifyLoadedDemo(identity("B", "/assets/b.js"), history(identity("A", "/assets/a.js"), false)))
      .toEqual({ capability: "quote", update: "none", observedCatalog: false });
  });

  it("uses compiled B capability even when identity history is unavailable", () => {
    expect(classifyLoadedDemo(null, null, "B"))
      .toEqual({ capability: "quote", update: "none", observedCatalog: false });
  });
});
