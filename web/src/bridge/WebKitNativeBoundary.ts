import { BridgeClientError } from "./protocol";

export interface NativeBoundary {
  postMessage(serializedMessage: string): Promise<unknown>;
}

export function createWebKitNativeBoundary(root: unknown = globalThis): NativeBoundary {
  const candidate = root as {
    webkit?: { messageHandlers?: { nativeHTTP?: { postMessage?: (message: string) => unknown } } };
  };
  const postMessage = candidate.webkit?.messageHandlers?.nativeHTTP?.postMessage;
  if (typeof postMessage !== "function") {
    throw new BridgeClientError(
      "BRIDGE_UNAVAILABLE",
      "Bridge unavailable: open this page in BridgeLab.",
    );
  }
  return {
    postMessage: (message) => Promise.resolve(postMessage.call(candidate.webkit?.messageHandlers?.nativeHTTP, message)),
  };
}
