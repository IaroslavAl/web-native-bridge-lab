import type { DemoHistoryRecord, LabVariant, WebIdentity } from "./webIdentity";

export interface LoadedDemo {
  capability: "catalog" | "quote";
  update: "none" | "unchanged" | "changed-a" | "changed-to-b";
  observedCatalog: boolean;
}

function sameIdentity(left: WebIdentity, right: WebIdentity): boolean {
  return left.variant === right.variant && left.entryPath === right.entryPath;
}

export function classifyLoadedDemo(
  current: WebIdentity | null,
  history: DemoHistoryRecord | null,
  compiledVariant: LabVariant = current?.variant ?? "A",
): LoadedDemo {
  const capability = compiledVariant === "B" ? "quote" : "catalog";
  if (!current || !history || !history.updateRequested) {
    return { capability, update: "none", observedCatalog: false };
  }

  const observedCatalog = history.catalogSeen && history.previous.variant === "A";
  if (current.variant === "A") {
    return {
      capability: "catalog",
      update: sameIdentity(current, history.previous) ? "unchanged" : "changed-a",
      observedCatalog,
    };
  }
  if (observedCatalog && !sameIdentity(current, history.previous)) {
    return { capability: "quote", update: "changed-to-b", observedCatalog: true };
  }
  return { capability: "quote", update: "none", observedCatalog: false };
}
