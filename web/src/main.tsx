import ReactDOM from "react-dom/client";
import { BridgeClient } from "./bridge/BridgeClient";
import { createWebKitNativeBoundary } from "./bridge/WebKitNativeBoundary";
import { App } from "./demo/App";
import { TechnicalPanel } from "./diagnostics/TechnicalPanel";
import {
  clearDemoHistory,
  createLoadedIdentity,
  selectWebSurface,
  type LabVariant,
  type StoragePort,
} from "./demo/webIdentity";
import "./styles.css";

const variant: LabVariant = __LAB_VARIANT__;
const identity = createLoadedIdentity(variant, import.meta.url);
const surface = selectWebSurface(window.location.search);
const createClient = () => new BridgeClient(createWebKitNativeBoundary(window));

function sessionStorageIfAvailable(): StoragePort | undefined {
  try { return window.sessionStorage; } catch { return undefined; }
}

const root = document.getElementById("root");
if (!root) throw new Error("Missing root element");

if (surface === "diagnostics") {
  const storage = sessionStorageIfAvailable();
  if (storage) clearDemoHistory(storage);
  let client: BridgeClient | null = null;
  let startupError: string | undefined;
  try {
    client = createClient();
  } catch (error) {
    startupError = error instanceof Error ? error.message : "Bridge unavailable.";
  }
  ReactDOM.createRoot(root).render(
    <TechnicalPanel client={client} variant={variant} startupError={startupError} />,
  );
} else {
  ReactDOM.createRoot(root).render(
    <App
      createClient={createClient}
      variant={variant}
      identity={identity}
      storage={sessionStorageIfAvailable()}
    />,
  );
}
