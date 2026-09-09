export type LabVariant = "A" | "B";

export interface WebIdentity {
  variant: LabVariant;
  entryPath: string;
}

export interface DemoHistoryRecord {
  v: 1;
  previous: WebIdentity;
  catalogSeen: boolean;
  updateRequested: true;
}

export interface StoragePort {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

export const WEB_HISTORY_KEY = "per85.explain.v1";
const ENTRY_PATH = /^\/assets\/[A-Za-z0-9._-]+\.js$/;
const MAX_ENTRY_PATH_LENGTH = 256;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, keys: string[]): boolean {
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  return actual.length === expected.length && actual.every((key, index) => key === expected[index]);
}

function isVariant(value: unknown): value is LabVariant {
  return value === "A" || value === "B";
}

function isEntryPath(value: unknown): value is string {
  return typeof value === "string" && value.length <= MAX_ENTRY_PATH_LENGTH && ENTRY_PATH.test(value);
}

function isIdentity(value: unknown): value is WebIdentity {
  return isRecord(value)
    && hasExactKeys(value, ["variant", "entryPath"])
    && isVariant(value.variant)
    && isEntryPath(value.entryPath);
}

function parseHistory(raw: string): DemoHistoryRecord | null {
  let value: unknown;
  try {
    value = JSON.parse(raw) as unknown;
  } catch {
    return null;
  }
  if (
    !isRecord(value)
    || !hasExactKeys(value, ["v", "previous", "catalogSeen", "updateRequested"])
    || value.v !== 1
    || !isIdentity(value.previous)
    || typeof value.catalogSeen !== "boolean"
    || value.updateRequested !== true
  ) return null;
  return value as unknown as DemoHistoryRecord;
}

export function createLoadedIdentity(variant: LabVariant, moduleUrl: string): WebIdentity | null {
  try {
    const entryPath = new URL(moduleUrl).pathname;
    return isEntryPath(entryPath) ? { variant, entryPath } : null;
  } catch {
    return null;
  }
}

export function selectWebSurface(search: string): "demo" | "diagnostics" {
  const mode = new URLSearchParams(search).getAll("mode");
  return mode.length === 1 && mode[0] === "diagnostics" ? "diagnostics" : "demo";
}

export function saveUpdateHistory(
  storage: StoragePort,
  previous: WebIdentity,
  catalogSeen: boolean,
): boolean {
  const record: DemoHistoryRecord = {
    v: 1,
    previous,
    catalogSeen,
    updateRequested: true,
  };
  try {
    storage.setItem(WEB_HISTORY_KEY, JSON.stringify(record));
    return true;
  } catch {
    return false;
  }
}

export function consumeDemoHistory(storage: StoragePort): DemoHistoryRecord | null {
  try {
    const raw = storage.getItem(WEB_HISTORY_KEY);
    storage.removeItem(WEB_HISTORY_KEY);
    return raw === null ? null : parseHistory(raw);
  } catch {
    return null;
  }
}

export function clearDemoHistory(storage: Pick<StoragePort, "removeItem">): void {
  try {
    storage.removeItem(WEB_HISTORY_KEY);
  } catch {
    // Storage is untrusted continuity only; diagnostics remains usable.
  }
}
