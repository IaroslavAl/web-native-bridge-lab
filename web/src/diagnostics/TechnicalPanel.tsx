import { useEffect, useMemo, useRef, useState } from "react";
import {
  BridgeClient,
} from "../bridge/BridgeClient";
import {
  BridgeClientError,
  TransportError,
  type BridgeRequestInput,
  type BridgeResponse,
  type PendingBridgeRequest,
} from "../bridge/protocol";
import { buildCatalogRequest, buildFixtureRequest, buildQuoteRequest } from "../demo/requestDefinitions";
import {
  ResponseInterpretationError,
  interpretBusinessFixture,
  interpretCatalog,
  interpretDelay,
  interpretQuote,
  type ScenarioName,
  type ScenarioResult,
} from "../demo/responseInterpreters";
import type { LabVariant } from "../demo/webIdentity";

interface TechnicalPanelProps {
  client: BridgeClient | null;
  variant: LabVariant;
  startupError?: string;
}

type Entry =
  | { id: number; label: string; status: "loading" }
  | { id: number; label: string; status: "result"; message: string }
  | { id: number; label: string; status: "error"; message: string };

type Interpreter = (response: BridgeResponse) => ScenarioResult;

function describeTechnicalError(error: unknown): string {
  if (error instanceof TransportError) return `transport ${error.code}: ${error.message}`;
  if (error instanceof ResponseInterpretationError) return `${error.category}: ${error.message}`;
  if (error instanceof BridgeClientError) return `${error.category} ${error.code}: ${error.message}`;
  return "protocol error: unexpected client failure";
}

export function TechnicalPanel({ client, variant, startupError }: TechnicalPanelProps) {
  const [scenario, setScenario] = useState<ScenarioName>(variant === "A" ? "catalog" : "quote");
  const [category, setCategory] = useState("books");
  const [sku, setSku] = useState("notebook");
  const [quantity, setQuantity] = useState(2);
  const [entries, setEntries] = useState<Entry[]>([]);
  const [cancelId, setCancelId] = useState<number | null>(null);
  const [connectionError, setConnectionError] = useState<string>();
  const pending = useRef(new Map<number, PendingBridgeRequest>());
  const mounted = useRef(true);

  useEffect(() => {
    mounted.current = true;
    if (!client) return () => { mounted.current = false; };
    const detach = client.attachPageLifecycle(window);
    void client.connect().catch((error: unknown) => {
      if (mounted.current) setConnectionError(describeTechnicalError(error));
    });
    return () => {
      mounted.current = false;
      detach();
    };
  }, [client]);

  const loadingCount = useMemo(
    () => entries.filter((entry) => entry.status === "loading").length,
    [entries],
  );
  const results = entries.filter((entry) => entry.status === "result");
  const errors = entries.filter((entry) => entry.status === "error");

  function runRequest(
    label: string,
    request: BridgeRequestInput,
    interpret: Interpreter,
    makeCancellable = true,
  ): PendingBridgeRequest | undefined {
    if (!client) return undefined;
    let operation: PendingBridgeRequest;
    try {
      operation = client.request(request);
    } catch (error) {
      setEntries((current) => [...current, {
        id: Date.now(), label, status: "error", message: describeTechnicalError(error),
      }]);
      return undefined;
    }
    pending.current.set(operation.id, operation);
    setEntries((current) => [...current, { id: operation.id, label, status: "loading" }]);
    if (makeCancellable) setCancelId(operation.id);
    void operation.promise
      .then(interpret)
      .then((result) => {
        if (!mounted.current) return;
        setEntries((current) => current.map((entry) => entry.id === operation.id
          ? { id: operation.id, label, status: "result", message: result.summary }
          : entry));
      })
      .catch((error: unknown) => {
        if (!mounted.current) return;
        setEntries((current) => current.map((entry) => entry.id === operation.id
          ? { id: operation.id, label, status: "error", message: describeTechnicalError(error) }
          : entry));
      })
      .finally(() => {
        pending.current.delete(operation.id);
        if (mounted.current) setCancelId((current) => current === operation.id ? null : current);
      });
    return operation;
  }

  function submitScenario() {
    if (scenario === "catalog") runRequest("Catalog", buildCatalogRequest(category), interpretCatalog);
    else runRequest("Quote", buildQuoteRequest(sku, quantity), interpretQuote);
  }

  function runConcurrent() {
    runRequest("Slow diagnostic", buildFixtureRequest(
      "/fixtures/delay?ms=10000&label=slow", 15000, "concurrent-slow",
    ), interpretDelay, true);
    runRequest("Fast diagnostic", buildFixtureRequest(
      "/fixtures/delay?ms=10&label=fast", 5000, "concurrent-fast",
    ), interpretDelay, false);
  }

  async function cancelCurrent() {
    if (cancelId === null) return;
    const operation = pending.current.get(cancelId);
    if (!operation) return;
    try {
      await operation.cancel();
    } catch (error) {
      setEntries((current) => current.map((entry) => entry.id === cancelId
        ? { id: entry.id, label: entry.label, status: "error", message: describeTechnicalError(error) }
        : entry));
    }
  }

  return (
    <main className="technical-shell">
      <header className="technical-header">
        <p className="eyebrow">Production bridge engineering surface</p>
        <h1>Diagnostics</h1>
        <p data-testid="lab.variant" aria-label="Lab variant" className="variant">
          Variant {variant} · {variant === "A" ? "Catalog default" : "Quote default"}
        </p>
      </header>

      <section className="card" aria-labelledby="scenario-heading">
        <h2 id="scenario-heading">Scenario</h2>
        <label>Scenario
          <select data-testid="lab.scenario" aria-label="Scenario" value={scenario}
            onChange={(event) => setScenario(event.target.value as ScenarioName)}>
            <option value="catalog">Catalog GET</option>
            <option value="quote">Quote POST</option>
          </select>
        </label>
        {scenario === "catalog" ? (
          <label>Category<input value={category} onChange={(event) => setCategory(event.target.value)} /></label>
        ) : (
          <div className="row">
            <label>SKU<input value={sku} onChange={(event) => setSku(event.target.value)} /></label>
            <label>Quantity<input type="number" min="1" max="5" value={quantity}
              onChange={(event) => setQuantity(Number(event.target.value))} /></label>
          </div>
        )}
        <button data-testid="lab.submit" onClick={submitScenario} disabled={!client}>Send through native HTTP</button>
      </section>

      <section className="card" aria-labelledby="diagnostics-heading">
        <h2 id="diagnostics-heading">Diagnostics</h2>
        <p>Every action below uses the same native bridge client. There is no browser fetch fallback.</p>
        <div className="actions">
          <button onClick={() => runRequest("HTTP fixture", buildFixtureRequest("/fixtures/http-error"), interpretCatalog)} disabled={!client}>HTTP error</button>
          <button onClick={() => runRequest("Business fixture", buildFixtureRequest("/fixtures/business-error"), interpretBusinessFixture)} disabled={!client}>Business error</button>
          <button onClick={() => runRequest("JSON fixture", buildFixtureRequest("/fixtures/malformed-json"), interpretCatalog)} disabled={!client}>Malformed JSON</button>
          <button onClick={() => runRequest("Timeout fixture", buildFixtureRequest("/fixtures/delay?ms=1000&label=timeout", 100), interpretDelay)} disabled={!client}>Native timeout</button>
          <button onClick={runConcurrent} disabled={!client}>Run concurrent requests</button>
          <button data-testid="lab.cancel" onClick={() => void cancelCurrent()} disabled={!client || cancelId === null}>Cancel active request</button>
        </div>
      </section>

      <section className="card status" aria-labelledby="status-heading" aria-live="polite">
        <h2 id="status-heading">Request status</h2>
        {loadingCount > 0 && <div data-testid="lab.loading">{loadingCount} {loadingCount === 1 ? "request" : "requests"} loading</div>}
        {results.length > 0 && <div data-testid="lab.result">{results.map((entry) => <p key={entry.id}><strong>{entry.label}:</strong> {entry.message}</p>)}</div>}
        {(startupError || connectionError || errors.length > 0) && (
          <div data-testid="lab.error" role="alert">
            {startupError && <p>{startupError}</p>}
            {connectionError && <p>{connectionError}</p>}
            {errors.map((entry) => <p key={entry.id}><strong>{entry.label}:</strong> {entry.message}</p>)}
          </div>
        )}
        {!startupError && !connectionError && loadingCount === 0 && results.length === 0 && errors.length === 0 && <p>No requests yet.</p>}
      </section>
    </main>
  );
}
