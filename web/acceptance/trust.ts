// Opt-in adversarial wire tests in the real installed shell, never a native seam.
// Intentionally bypass TS client validation to exercise WebKit/native validation.
import { createWebKitNativeBoundary } from "../src/bridge/WebKitNativeBoundary";

const bytes = (value: string) => new TextEncoder().encode(value).length;
const pause = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));
function check(value: boolean, field: string): asserts value {
  if (!value) throw new Error(field);
}
type Reply = Record<string, unknown>;

export async function trustMatrix(record: (line: string) => void) {
  const boundary = createWebKitNativeBoundary(window);
  const raw = async (value: unknown): Promise<Reply> => {
    const result = await boundary.postMessage(value as string);
    check(typeof result === "object" && result !== null && !Array.isArray(result), "wire reply object");
    return result as Reply;
  };
  const post = (value: unknown) => raw(JSON.stringify(value));
  const error = (reply: Reply, code: string, id: number | null) => {
    check(Object.keys(reply).sort().join() === "code,id,message,type,v", "closed error envelope");
    check(reply.v === 1 && reply.type === "error", "v1 error envelope");
    check(reply.code === code, `wire code ${String(reply.code)}, expected ${code}`);
    check(reply.id === id, `wire id ${String(reply.id)}, expected ${id}`);
    check(typeof reply.message === "string" && reply.message.length > 0 && reply.message.length <= 256, "bounded diagnostic");
  };
  const hello = await post({ v: 1, type: "hello" });
  check(hello.type === "helloAck" && hello.v === 1 && typeof hello.session === "string" && /^[0-9a-f]{32}$/.test(hello.session), "hello session shape");
  const session = hello.session;
  let nextId = 1;
  const request = (path: string, tag: string, extra: Record<string, unknown> = {}) => ({
    v: 1, type: "request", session, id: nextId++, method: "GET",
    url: `http://127.0.0.1:8788${path}`, headers: { "x-lab-tag": tag }, body: null, timeoutMs: 15000, ...extra,
  });
  const denied = async (message: ReturnType<typeof request>, code: string) => error(await post(message), code, message.id);
  const response = async (message: Record<string, unknown> & { id: number }) => {
    const reply = await post(message);
    check(reply.v === 1 && reply.type === "response" && reply.id === message.id && reply.status === 200, `response envelope for ${message.id}: ${JSON.stringify(reply).slice(0, 250)}`);
    return reply;
  };

  for (const value of [2, "1", null, true]) {
    error(await post({ v: value, type: "hello", id: 7 }), "UNSUPPORTED_VERSION", 7);
  }
  error(await post({ type: "hello" }), "UNSUPPORTED_VERSION", null);
  for (const value of ["{", "[]", JSON.stringify({ v: 1, type: "hello", extra: true })]) {
    error(await raw(value), "INVALID_REQUEST", null);
  }
  error(await raw({ v: 1, type: "hello" }), "INVALID_REQUEST", null);
  const base = request("/fixtures/echo", "s3-denied-wire");
  for (const id of [0, -1, 1.5, 2147483648, 9223372036854775808, true]) {
    error(await post({ ...base, id }), "INVALID_REQUEST", null);
  }
  for (const changed of [{ extra: true }, { session: "bad" }, { session: undefined }]) {
    error(await post({ ...base, ...changed }), "INVALID_REQUEST", base.id);
  }
  const wrongSession = (session[0] === "0" ? "1" : "0") + session.slice(1);
  error(await post({ ...base, session: wrongSession }), "ORIGIN_DENIED", base.id);
  error(await post({ v: 1, type: "cancel", session: wrongSession, id: base.id }), "ORIGIN_DENIED", base.id);
  // The same id is still usable after all structural/session failures.
  const body = "🙂".repeat(16384);
  check(bytes(body) === 65536, "request body exact UTF-8 bytes");
  const echo = { ...base, method: "POST", headers: { "content-type": "text/plain", "x-lab-tag": "s3-body-limit" }, body };
  check((await response(echo)).body === body, "65536-byte Unicode exact echo");
  error(await post(echo), "INVALID_REQUEST", base.id);
  check((await post({ v: 1, type: "hello" })).session === session, "repeated hello preserves session");
  error(await post(echo), "INVALID_REQUEST", base.id);
  const cancelled = await post({ v: 1, type: "cancel", session, id: base.id });
  check(cancelled.type === "cancelAck" && cancelled.id === base.id && cancelled.cancelled === false, "completed raw cancel ack");
  record("Closed wire, numeric/session validation and high-water PASS");

  const padded = JSON.stringify({ v: 1, type: "hello" });
  const exactRaw = padded + " ".repeat(131072 - bytes(padded));
  check(bytes(exactRaw) === 131072, "raw exact byte count");
  check((await raw(exactRaw)).session === session, "raw exact cap hello accepted");
  error(await raw(exactRaw + " "), "MESSAGE_TOO_LARGE", null);
  const unicodeRaw = JSON.stringify({ v: 1, type: "hello", extra: "🙂".repeat(32768) });
  check(bytes(unicodeRaw) > 131072 && unicodeRaw.length < 131072, "raw Unicode byte versus code-unit distinction");
  error(await raw(unicodeRaw), "MESSAGE_TOO_LARGE", null);
  await denied(request("/fixtures/echo", "s3-denied-body", {
    method: "POST", headers: { "content-type": "text/plain", "x-lab-tag": "s3-denied-body" }, body: body + "x",
  }), "REQUEST_TOO_LARGE");
  record("Raw 131072/+1 and Unicode body 65536/+1 PASS");

  for (const url of ["http://localhost:8788/healthz", "http://127.0.0.1:8787/healthz", "https://127.0.0.1:8788/healthz", "http://127.0.0.1/healthz"]) {
    await denied(request("/healthz", "s3-denied-origin", { url }), "URL_DENIED");
  }
  for (const url of ["/healthz", "http://127.0.0.1:8788/healthz#", "http://user@127.0.0.1:8788/healthz", "http://127.0.0.1:8788/%0a", "http://127.0.0.1:8788/%GG"]) {
    await denied(request("/healthz", "s3-denied-url", { url }), "INVALID_REQUEST");
  }
  for (const headers of [{ Authorization: "synthetic" }, { cookie: "synthetic=1" }, { Host: "127.0.0.1" }, { Accept: "*/*" }, { "x-lab-tag": "bad\r\nvalue" }, { "x-lab-tag": "x".repeat(129) }]) {
    await denied(request("/healthz", "s3-denied-header", { headers }), "INVALID_REQUEST");
  }
  for (const kind of ["same", "cross", "loop"]) {
    await denied(request(`/fixtures/redirect-${kind}`, `s3-redirect-${kind}`), "REDIRECT_DENIED");
  }
  record("API origin, URL/header denial and redirects PASS");

  const hostile = "'\"\\\n</script><script>document.title='s3-executed'</script><img src='/stage3-injected' onerror=\"document.title='s3-executed'\">🙂\u2028\u2029";
  const originalTitle = document.title;
  const originalURL = location.href;
  const echoed = await response(request("/fixtures/echo", "s3-hostile", {
    method: "POST", headers: { "content-type": "text/plain", "x-lab-tag": "s3-hostile" }, body: hostile,
  }));
  check(echoed.body === hostile, "hostile reply exact bytes/text");
  record(String(echoed.body)); // React text child, not HTML injection.
  await pause(100);
  check(document.title === originalTitle && location.href === originalURL, "hostile reply did not execute or navigate");
  check(!document.querySelector("img[src='/stage3-injected']"), "hostile text did not create element");
  record("Hostile response rendered as inert text PASS");

  const large = await response(request("/fixtures/large?bytes=1048576", "s3-response-limit"));
  check(large.body === "x".repeat(1048576), "chunked response exact 1048576 bytes");
  await denied(request("/fixtures/large?bytes=1048577", "s3-response-over"), "RESPONSE_TOO_LARGE");
  await denied(request("/fixtures/binary", "s3-binary"), "UNSUPPORTED_RESPONSE");
  await denied(request("/fixtures/invalid-utf8", "s3-encoding"), "RESPONSE_ENCODING");
  record("Chunked response 1048576/+1, binary and UTF-8 PASS");

  let settled = 0;
  const messages = Array.from({ length: 8 }, (_, i) => request(`/fixtures/delay?ms=3000&label=slot-${i}`, `s3-slot-${i}`));
  const pending = messages.map((message, i) => response(message).then((reply) => {
    check((reply.headers as Record<string, string>)["x-lab-tag"] === `s3-slot-${i}`, `slot ${i} header correlation`);
    check(reply.body === JSON.stringify({ label: `slot-${i}`, delayedMs: 3000 }), `slot ${i} body correlation`);
    settled++;
  }));
  await denied(request("/fixtures/delay?ms=3000&label=busy", "s3-busy"), "BUSY");
  check(settled === 0, "BUSY before any of eight requests completed");
  error(await post(messages[0]), "INVALID_REQUEST", messages[0].id);
  await Promise.all(pending);
  check(Number(settled) === 8, "eight actual correlated terminal responses");
  record("Eight admitted, ninth BUSY, active duplicate isolated PASS");

  // Production CSP intentionally prevents these documents from loading. This is
  // denied-before-bridge evidence, NOT foreign-frame handler execution evidence.
  for (const [kind, origin] of [["same", "http://127.0.0.1:8787"], ["foreign", "http://127.0.0.1:8788"]]) {
    const url = `${origin}/stage3-frame-${kind}.html`;
    const violations: SecurityPolicyViolationEvent[] = [];
    const listener = (event: SecurityPolicyViolationEvent) => violations.push(event);
    document.addEventListener("securitypolicyviolation", listener);
    const frame = document.createElement("iframe");
    try {
      frame.src = url;
      document.body.append(frame);
      await pause(250);
      check(violations.some((event) => event.effectiveDirective === "frame-src" && event.blockedURI.startsWith(origin)), `CSP ${kind} frame-src violation`);
    } finally {
      frame.remove();
      document.removeEventListener("securitypolicyviolation", listener);
    }
  }
  check((await post({ v: 1, type: "hello" })).session === session, "denied frames preserve live main session");
  record("Same/foreign frames blocked by production CSP before bridge PASS");
  record("Trust and limits matrix PASS");
}
