import ReactDOM from "react-dom/client";
import { App, type LabVariant } from "./App";
import { BridgeClient, createWebKitNativeBoundary } from "./bridgeClient";
import "./styles.css";

const variant: LabVariant = __LAB_VARIANT__;
let client: BridgeClient | null = null;
let startupError: string | undefined;

try {
  client = new BridgeClient(createWebKitNativeBoundary(window));
} catch (error) {
  startupError = error instanceof Error ? error.message : "Bridge unavailable.";
}

const root = document.getElementById("root");
if (!root) throw new Error("Missing root element");

ReactDOM.createRoot(root).render(
  <App client={client} variant={variant} startupError={startupError} />,
);
