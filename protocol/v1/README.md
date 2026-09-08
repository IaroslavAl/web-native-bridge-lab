# Bridge protocol v1 — normative wire and transport contract

Status: independently reviewed foundation, implemented by the integrated candidate; final integration/owner acceptance is separate. Scope: synthetic-data, loopback, Simulator-only lab. This document owns wire semantics and limits; `schema.json` owns structural validation. Both are required. OpenSpec owns observable requirements; business fixtures belong to `docs/architecture.md`, never native production sources.

## Boundary and message shapes

The page calls `window.webkit.messageHandlers.nativeHTTP.postMessage(JSON.stringify(message))` in the page content world. Register `WKScriptMessageHandlerWithReply` as `nativeHTTP`. Each invocation returns a Promise of a JSON-compatible reply object, not a JSON string. Use WebKit reply-handler serialization, never concatenate values into executable JavaScript. There is no injected global callback, fetch fallback, or native business API. Web serializes the envelope once; native bounds its UTF-8 bytes before parsing it. Reject non-string inputs. Envelope parsing is generic JSON parsing, not decoding the HTTP body as business JSON.

The schema defines these closed objects (all listed fields required; no unknown fields):

- hello: `{v:1,type:"hello"}`; no HTTP work. Web sends once after document load and awaits the reply before requests.
- helloAck: `{v:1,type:"helloAck",session}`; session is the native-generated 32-lowercase-hex document token.
- request: `{v:1,type:"request",session,id,method,url,headers,body,timeoutMs}`.
- cancel: `{v:1,type:"cancel",session,id}`; id targets an existing request in this document.
- response: `{v:1,type:"response",id,status,headers,body}`. HTTP body is always a string, including empty string.
- error: `{v:1,type:"error",id,code,message}`. `id:null` only when no valid bounded integer id is recoverable. Stable code is machine-readable; message is a sanitized nonempty diagnostic, at most 256 characters, never URL/body/credentials.
- cancelAck: `{v:1,type:"cancelAck",id,cancelled}`. This settles the cancel invocation, not the original request invocation.

IDs are integers 1 through 2147483647, monotonically increasing for requests within one document. The TS client allocates starting at 1 and never wraps. Native holds a high-water mark, not an unbounded completed-ID set. After v1 request structural and session validation, a new valid id above the mark is consumed even if later semantic request validation or admission fails. A structurally invalid request does not consume an id. Duplicate or lower ids get `INVALID_REQUEST` on their own invocation without touching an earlier task. A cancel does not advance the mark. After exhaustion the client must reload before new requests. Native associates each invocation with its own document-generation token, not with page-supplied authority. New documents may restart IDs at 1. Out-of-order replies are matched to their original id and Promise; mismatch is a client protocol failure, never another request's result.

## Validation order and errors

Native creates a fresh random session token on each trusted main-document commit and invalidates it on revocation. Repeated hello in the same live document returns the same token and never resets ids or tasks. The hello reply is tied to its originating WebKit Promise; a queued hello from a destroyed document cannot install the token in a new document. Every request/cancel must echo the current token: after structural validation but before id consumption, a well-shaped stale/wrong token returns ORIGIN_DENIED with recoverable id and no work. Missing/malformed token is INVALID_REQUEST. This token is generation binding, not authentication and not a substitute for origin/frame checks. Do not attempt to distinguish same-URL reloads from URL alone. Session never enters the generic HTTP executor or HTTP headers. The client clears it on pagehide; a newly loaded client performs hello again.

Check, in order: trusted main-frame document and active generation; raw message type/byte limit; JSON syntax/object; supported version; message shape, session binding and request id ordering; request limits/URL/headers; available concurrency; network. First failing check determines the code. For a trusted parseable object whose `v` is not numeric 1 (including missing/string version), return v1 `UNSUPPORTED_VERSION` without starting network work. Other malformed structures use `INVALID_REQUEST`. Trusted oversize raw messages use `MESSAGE_TOO_LARGE`, id null without parsing. Untrusted/inactive messages use `ORIGIN_DENIED`, id null, without parsing; reply only to the originating invocation, never by evaluating script in the current page.

| Code | Meaning / owner |
| --- | --- |
| ORIGIN_DENIED | Adapter denies sender frame/origin/generation |
| MESSAGE_TOO_LARGE | Adapter raw message exceeds cap |
| UNSUPPORTED_VERSION | Adapter cannot interpret requested version |
| INVALID_REQUEST | Bad shape/id/method/URL syntax/header/body type/timeout |
| URL_DENIED | Syntactically valid URL outside the exact API origin |
| REQUEST_TOO_LARGE | Body UTF-8 byte cap exceeded |
| BUSY | Eight live requests already occupy this document's executor |
| REDIRECT_DENIED | HTTP 301, 302, 303, 307 or 308; no hop followed |
| RESPONSE_TOO_LARGE | Decoded response data or exposed response headers exceed cap |
| UNSUPPORTED_RESPONSE | Nonempty response is not an allowed textual media type |
| RESPONSE_ENCODING | Response bytes are not valid UTF-8 |
| TIMEOUT | Native monotonic wall-clock deadline wins |
| CANCELLED | Explicit cancel, navigation/reload/close/teardown wins |
| NETWORK_ERROR | Other network failure, including connection refusal or auth challenge |

No automatic retry. Non-redirect HTTP statuses (including 4xx/5xx and 304) are ordinary `response` envelopes. React separately classifies HTTP failure, malformed JSON, and business validation failure. Invalid JSON is NOT a native error. No native `ok` or business error field.

## Exact origin and URL policies

Two independent native-owned immutable policies:

1. Trusted page origin is exactly `(http, 127.0.0.1, 8787)` and `frameInfo.isMainFrame == true`. Check WebKit's security origin AND the committed main document URL/generation. Do not trust a field in the message or a URL string prefix. Same-origin iframes are denied too. No bridge admission until trusted main document commit. Subframes/new windows/external main-frame navigation are blocked; do not open Safari. An allowed main-frame navigation, reload, provisional failure, web-process termination, close or adapter destruction revokes the old generation and cancels its tasks before reuse. A rejected navigation attempt does not revoke the unchanged current document.
2. API request origin is exactly `(http, 127.0.0.1, 8788)`. Every path is permitted by this transport policy; there is deliberately no business endpoint registry. Only GET/POST. Require absolute ASCII URL with explicit port and `/` path, maximum 8192 characters. Reject userinfo, fragments (even empty `#`), backslashes, literal whitespace/control characters, invalid percent escapes and percent-encoded control characters as `INVALID_REQUEST`. Parse once with URLComponents and compare parsed scheme, host and port; additionally require literal authority `127.0.0.1:8788` for allowed requests. Alternative numeric forms, localhost, IPv6, omitted port, trailing-dot host, different port and HTTPS are not the allowed origin. Syntactically valid alternatives return `URL_DENIED`, never resolve DNS. Relative URLs are invalid. Web constructs the complete URL using URL/URLSearchParams from base host, path and query; native receives no separate query bag, makes no business substitutions, and preserves query semantics.

URL syntax checks precede the allowlist. Percent encoding in path/query is allowed except encoded controls. Reject all redirect statuses listed above before any destination request, including same-origin redirects, malformed/missing Location and loops. URLSession redirect delegate must never follow; also classify the final status in case a transport seam supplies a redirect response without a delegate callback. No WebView policy check substitutes for API enforcement.

## Headers, body, credentials and limits

Request header names must already be lowercase and are restricted to `accept`, `content-type`, `x-lab-tag`; unknown or mixed-case names are invalid rather than silently stripped. Values contain printable ASCII only, 1–128 characters. `accept` permits exactly `application/json`, `text/plain`, or `*/*`. `content-type` permits exactly `application/json` or `text/plain`. GET requires body null and no content-type. POST requires string body (empty allowed) and content-type. Body is opaque UTF-8 text, not an object or base64. No multipart, file, binary, stream, upload URL, cookie or authorization capability.

Native uses a dedicated ephemeral URLSession with no shared credential storage, no cookie storage/acceptance, no URL cache, reload-ignoring-cache policy and no ambient authentication. Cancel authentication challenges; no keychain lookup or user prompts. Reject caller-supplied Cookie, Authorization, Host and framing headers through the header allowlist. HTTP library-generated Host/Content-Length and other standard framing are permitted, never caller-overridden. Never expose Set-Cookie, authentication or arbitrary server headers. WebView uses a nonpersistent data store. Fixture services send no cookies and no CORS permission; CSP disables fetch/XHR/WebSocket connections (`connect-src 'none'`). This is defense in depth, not a claim that arbitrary trusted-page JavaScript is safe.

| Bound | Exact rule |
| --- | --- |
| Raw incoming bridge message | 131072 UTF-8 bytes inclusive, before parsing |
| URL | 8192 ASCII characters inclusive |
| Request body | 65536 UTF-8 bytes inclusive; measure bytes, not Swift graphemes/JS code units |
| Request headers | At most the three allowed entries; per-value cap above |
| Native concurrency | At most 8 accepted live requests per adapter/executor; no queue; ninth receives BUSY |
| Deadline | Required integer timeoutMs 1–30000 inclusive; TS default 5000; monotonic deadline from native admission, includes headers and all body chunks |
| Response data | 1048576 bytes inclusive after HTTP content decoding; cancel as soon as streaming delegate would cross bound; do not buffer an unbounded data(for:) result |
| Exposed response headers | Only content-type and x-lab-tag; lowercase names; printable ASCII values; combined UTF-8 bytes of names plus values at most 8192; over cap is RESPONSE_TOO_LARGE, invalid characters are UNSUPPORTED_RESPONSE |

Do not rely only on Content-Length or URLSession inactivity timeouts. Cap bytes actually delivered; an early declared length over cap may be rejected conservatively. OS/framework header buffering and decompressor internals are not under this application cap and are a disclosed non-production limitation. Omit all unexposed response headers before sizing. If repeated exposed headers arrive, join values with `, ` in arrival order (or preserve the HTTP library's already combined value). For a nonempty response, Content-Type media type (case-insensitive, ignoring parameters) must be `application/json` or `text/plain`; otherwise UNSUPPORTED_RESPONSE. Empty responses need no Content-Type. Bytes must strictly decode as UTF-8 regardless of charset parameter; invalid sequences fail, never lossy replacement. Return body unchanged, including quotes, markup and Unicode. Response envelopes can be larger than raw request cap due to JSON escaping; they are not subject to that incoming cap and remain bounded by data/header limits.

## Completion, cancellation and document lifetime

Serialize admission and terminal decisions (actor/serial queue). Each accepted request has one native task, deadline and reply handle. First terminal event wins; remove the task and cancel deadline exactly once. On timeout/cancel/size failure, cancel the underlying URLSession task; late chunks/completions cannot settle again. A timeout must stop native network work even if JavaScript stops running. Cancellation does not promise rollback of server side effects.

For valid cancel targeting an active id in this generation, atomically resolve the original request with CANCELLED, cancel underlying work and return cancelAck cancelled:true. Unknown/completed ids return cancelled:false with no network work. If response wins first, a later cancel returns false. If cancel wins first, later response is ignored. Deadline and response races follow the same first-terminal rule, not wall-clock guesses in JS.

On document revocation, cancel all native tasks and settle/retire originating reply handles with CANCELLED exactly once; WebKit may discard delivery to a destroyed JS context. A new document must never receive old results, even if it uses the same integer ids. Drain/retire prior tasks before admitting the new generation so executor concurrency is not accumulated across reloads. The adapter must remove message handlers on teardown and avoid retain cycles. TS client pagehide cleanup sends best-effort cancels, but native revocation is authoritative. TS must not substitute its own timer for the native deadline; a missing bridge is an immediate local `BRIDGE_UNAVAILABLE` UI error, not a wire code. Unknown/malformed native replies are local `PROTOCOL_ERROR`, never interpreted as a business success.

## Validation and conformance

`schema.json` uses JSON Schema draft-07.
Request body byte limits are deliberately semantic-only: schema validation must not turn a 65537-byte ASCII POST into INVALID_REQUEST before native can report REQUEST_TOO_LARGE. JSON Schema character counts cannot enforce UTF-8 byte counts. Examples contain decoded envelopes, the string passed to WebKit is JSON.stringify of the request/cancel envelope. `examples.json` labels structurally valid, structurally invalid and semantic-only vectors separately. Schema success does not prove UTF-8 byte caps, URL canonicalization, lifetime or actual HTTP behavior; see requirement-to-test matrix. Test adapters and native with the same contract fixtures. Native unit tests may inject a loopback origin/ephemeral port policy explicitly; the shipping Simulator app policy must remain the fixed two origins above, not page-configurable.
