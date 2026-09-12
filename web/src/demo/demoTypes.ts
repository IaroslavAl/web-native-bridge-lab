import type { ScenarioResult } from "./responseInterpreters";

export type DemoAction = "catalog" | "quote" | "reload";
export type Connection = "connecting" | "ready" | "error";

export interface DemoError {
  title: string;
  detail: string;
  responseReceived: boolean;
}

export type Operation =
  | { kind: "idle" }
  | { kind: "pending"; action: DemoAction }
  | { kind: "result"; action: "catalog" | "quote"; result: ScenarioResult }
  | { kind: "error"; action: "catalog" | "quote"; error: DemoError };
