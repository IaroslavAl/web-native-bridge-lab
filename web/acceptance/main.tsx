// Test-only remotely served React page. No native test seam, mock, fetch, or injection.
// Uses the exact production client and business interpreters in the installed shell.
import { useState } from "react";
import ReactDOM from "react-dom/client";
import { trustMatrix } from "./trust";
import { BridgeClient, createWebKitNativeBoundary, TransportError, type BridgeResponse } from "../src/bridgeClient";
import { buildFixtureRequest, buildQuoteRequest, interpretCatalog, interpretBusinessFixture,
  interpretQuote, interpretDelay, ResponseInterpretationError } from "../src/scenarios";

const client = new BridgeClient(createWebKitNativeBoundary(window));
client.attachPageLifecycle(window);
const pause = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

function check(condition: boolean, field: string): asserts condition {
  if (!condition) throw new Error(field);
}

function interpretation(response: BridgeResponse, parse: (value: BridgeResponse) => unknown,
                        category: string, message: string) {
  try { parse(response); }
  catch (error) {
    check(error instanceof ResponseInterpretationError, "interpreter error type");
    check(error.category === category, `interpreter category: ${error.category}`);
    check(error.message === message, `interpreter message: ${error.message}`);
    return;
  }
  throw new Error("interpreter incorrectly accepted response");
}

async function errorCode(operation: ReturnType<BridgeClient["request"]>, code: string) {
  try { await operation.promise; }
  catch (error) {
    check(error instanceof TransportError, "transport error type");
    check(error.code === code, `transport code: ${error.code}, expected ${code}`);
    check(error.requestId === operation.id, "transport request correlation");
    return;
  }
  throw new Error(`missing transport error ${code}`);
}

function Page() {
  const [lines, setLines] = useState<string[]>([]);
  const [running, setRunning] = useState(false);
  const [complete, setComplete] = useState(false);
  const record = (line: string) => setLines((previous) => [...previous, line]);
  const fail = (error: unknown) => record(`FAIL: ${error instanceof Error ? error.message : String(error)}`);

  async function matrix() {
    setRunning(true);
    await client.connect();
    const http = await client.request(buildFixtureRequest("/fixtures/http-error", 5000, "s2-http")).promise;
    check(http.status === 503, "HTTP status 503");
    check(http.body === '{"error":{"code":"UNAVAILABLE","message":"Try later"}}', "HTTP 503 opaque body");
    interpretation(http, interpretCatalog, "HTTP", `HTTP 503: ${http.body}`);
    record("HTTP 503 preserved");

    const quoteInput = buildQuoteRequest("notebook", 0);
    quoteInput.headers["x-lab-tag"] = "s2-quote";
    const quote = await client.request(quoteInput).promise;
    check(quote.status === 422, "HTTP status 422");
    check(quote.body === '{"error":{"code":"INVALID_QUANTITY","message":"Quantity must be 1 to 5"}}', "HTTP 422 opaque body");
    interpretation(quote, interpretQuote, "HTTP", `HTTP 422: ${quote.body}`);
    record("HTTP 422 preserved");

    const business = await client.request(buildFixtureRequest("/fixtures/business-error", 5000, "s2-business")).promise;
    check(business.status === 200, "business HTTP status");
    interpretation(business, interpretBusinessFixture, "business", "OUT_OF_STOCK: Not available");
    record("Business error interpreted");

    const malformed = await client.request(buildFixtureRequest("/fixtures/malformed-json", 5000, "s2-json")).promise;
    check(malformed.status === 200 && malformed.body === '{"broken":', "invalid JSON opaque status/body");
    interpretation(malformed, interpretCatalog, "JSON parse", "Response body is not valid JSON.");
    record("Malformed JSON preserved");

    // No JS deadline/race: wait for the actual native timeout error.
    await errorCode(client.request(buildFixtureRequest("/fixtures/delay?ms=2000&label=timeout", 500, "s2-timeout")), "TIMEOUT");
    record("Native TIMEOUT");

    const cancelled = client.request(buildFixtureRequest("/fixtures/delay?ms=2000&label=cancel", 5000, "s2-cancel"));
    const terminal = errorCode(cancelled, "CANCELLED");
    await pause(500); // schedule an explicit cancel; backend log MUST show connection-close
    check(await cancelled.cancel(), "active cancel acknowledgement");
    await terminal;
    check(!(await cancelled.cancel()), "completed cancel acknowledgement");
    record("Explicit CANCELLED");

    const order: string[] = [];
    const slow = client.request(buildFixtureRequest("/fixtures/delay?ms=1500&label=slow", 5000, "s2-slow"));
    const fast = client.request(buildFixtureRequest("/fixtures/delay?ms=10&label=fast", 5000, "s2-fast"));
    check(slow.id !== fast.id, "distinct concurrent ids");
    await Promise.all([[slow, "slow", 1500], [fast, "fast", 10]].map(async ([op, label, ms]) => {
      const operation = op as typeof slow;
      const response = await operation.promise;
      check(response.id === operation.id, `concurrent ${label} id`);
      check(response.headers["x-lab-tag"] === `s2-${label}`, `concurrent ${label} response tag`);
      check(interpretDelay(response).summary === `${label} — ${ms} ms`, `concurrent ${label} body`);
      order.push(String(label));
    }));
    check(order.join(",") === "fast,slow", `concurrent order: ${order}`);
    record("Concurrent fast then slow");
    await pause(2200); // observe beyond cancelled fixture deadlines; host rejects late 200 events
    record("Outcome matrix PASS");
    setComplete(true);
  }

  async function networkOff() {
    await errorCode(client.request(buildFixtureRequest("/fixtures/http-error", 5000, "s2-network-off")), "NETWORK_ERROR");
    record("NETWORK_ERROR after backend stop");
  }

  return <main>
    <h1>Stage2 test-only outcomes</h1>
    <button disabled={running} onClick={() => void matrix().catch(fail)}>Run outcome probes</button>
    <button disabled={running} onClick={() => { setRunning(true); void trustMatrix(record).catch(fail); }}>Run trust probes</button>
    <button disabled={!complete} onClick={() => void networkOff().catch(fail)}>Probe stopped backend</button>
    {lines.map((line, index) => <p key={index}>{line}</p>)}
  </main>;
}

ReactDOM.createRoot(document.getElementById("root")!).render(<Page />);
