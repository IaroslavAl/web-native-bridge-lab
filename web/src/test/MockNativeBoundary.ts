import type { NativeBoundary } from "../bridge/WebKitNativeBoundary";

// Test-only explicit mock. This file is never imported by production entry points.
export class MockNativeBoundary implements NativeBoundary {
  readonly messages: string[] = [];

  constructor(
    private readonly responder: (message: Record<string, unknown>) => unknown | Promise<unknown>,
  ) {}

  async postMessage(serializedMessage: string): Promise<unknown> {
    this.messages.push(serializedMessage);
    return this.responder(JSON.parse(serializedMessage) as Record<string, unknown>);
  }

  decodedMessages(): Array<Record<string, unknown>> {
    return this.messages.map((message) => JSON.parse(message) as Record<string, unknown>);
  }
}
