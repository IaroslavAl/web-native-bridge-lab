# Web–Native Bridge Lab architecture and implementation handoff

Status: proposed foundation, not an implemented app. Approved product intent: [OWNER_MISSION](agent/OWNER_MISSION.md). Observable requirements: `openspec/changes/add-bridge-lab/specs/`. Normative wire/security/lifecycle limits: [protocol v1](../protocol/v1/README.md). Requirement/test mapping: [verification plan](verification-plan.md). Do not copy business types into native production code.

## Small module graph

React scenario → TS bridge client → WebKit reply message handler → generic Swift executor → URLSession → synthetic HTTP fixture. Opaque status/allowed headers/body return along the same path. React alone parses domain JSON and renders it. Static asset traffic is normal WebView networking on port 8787; scenario API traffic must originate in the native executor on 8788.

| Owner/card phase | Paths and output | Dependency / constraints |
| --- | --- | --- |
| Foundation | openspec/, protocol/v1/, docs/architecture.md, docs/verification-plan.md, foundation evidence, initial .gitignore | No module implementation; independent spec review releases consumers |
| Backend | backend/, scripts/lab | Node built-in HTTP/filesystem/process APIs; dependency-free where practical; separate loopback web/API listeners; owns start/status/stop and its tests |
| Transport | native/TransportPackage/ | Swift package, product/module TransportPackage, Swift tools 5.9+, Foundation only; no WebKit/UIKit/business models; Swift unit tests |
| iOS bridge | ios/ | Swift app plus adapter and Simulator tests; links local TransportPackage; deployment target iOS 17.0; app name/scheme BridgeLab, bundle ID lab.webnative.BridgeLab; checked-in reproducible Xcode project; no signing required for Simulator |
| Web | web/ | React + TypeScript + Vite; own package.json and exact lockfile; unit tests with explicitly mocked native boundary; production assets in web/dist |
| Integration | scripts/verify, top-level README/run instructions, bounded cross-module fixes, OpenSpec task evidence | Merge exact reviewed parent commits; complete actual Simulator gates and same-binary evidence |
| Acceptance | Read-only exact integrated RC | Independent Simulator/product/security/lifecycle verification; do not fix source or invent evidence |

No shared root application package/workspace manifest: each module owns its tooling. OpenSpec/Ajv tooling is isolated in `openspec/tooling`. Backend does not edit/build web sources. Web does not edit backend/native. Integration alone owns top-level reproducibility instructions and `scripts/verify`; backend alone owns `scripts/lab`. Consumers merge the reviewed foundation head into their own assigned branches, preserving commit identities; do not use primary main as evidence of available dependencies.

## Cross-module Swift seam (technical decision, to implement later)

Before HTTP requests the TS client performs the v1 hello/helloAck handshake, retains the native-generated document session, and echoes it on request/cancel envelopes. The adapter compares that token on every invocation; repeated hello cannot reset request ids. This closes same-URL reload/queued-message ambiguity without adding WebKit state to TransportPackage. Full ordering and error rules are in the protocol.

Public module `TransportPackage` exports:

- `HTTPRequest`: value with public initializer and fields `id: Int`, `method: String`, `url: String`, `headers: [String: String]`, `body: String?`, `timeoutMs: Int`.
- `HTTPResponse`: `id: Int`, `status: Int`, `headers: [String: String]`, `body: String`.
- `TransportFailure`: `id: Int`, `code: String`, `message: String` (codes from protocol).
- `HTTPResult`: enum `.response(HTTPResponse)` or `.failure(TransportFailure)`.
- `TransportPolicy`: immutable configuration initialized with `allowedOrigin: URL`; executor enforces protocol caps and GET/POST policy. The app supplies only `http://127.0.0.1:8788`. Tests may inject an isolated loopback port. This is native-owned, never wire-configurable.
- `HTTPExecutor`: actor initialized with `policy: TransportPolicy`; `execute(_ request: HTTPRequest) async -> HTTPResult`, `cancel(id: Int) async -> Bool`, `cancelAll() async`. Public value initializers and Sendable values permit use from the adapter/tests. execute does not throw for expected transport errors; cancel true means it won an active request's terminal decision. cancelAll resolves outstanding executes as CANCELLED.
- Coordinator-approved lifecycle extension (stage A, not full adapter acceptance): `submit(_ request: HTTPRequest) -> HTTPSubmission` is actor-isolated (external callers `await`). It returns `.immediate(HTTPResult)` for rejection or `.running(HTTPExecution)` only after active task/deadline registration, without waiting for HTTP completion or capacity. `HTTPExecution` is a Sendable reference with a native UUID `id` and `result() async -> HTTPResult`; its immutable terminal value can be read even when selected before the first waiter. Only the executor creates/resolves receipts, and retains no completed-receipt history. `execute` remains a compatible submit-and-await wrapper; cancel/cancelAll, validation precedence, eight-task cap, UUID guards and deadlines are unchanged.

Admission callers must sequence revocation after the short submission acknowledgement, not after the HTTP lifetime. Synchronous document ingress fencing does not rewrite a terminal selected by the executor before ordered cancelAll (including overlap before cancelAll reaches that actor). Publish the selected value only on its immutable originating reply handle; drain old publications before fresh activation. See the accepted ordering model in `ios/LIFECYCLE_REPLAN.md`. Stage A provides a WebKit-independent `BridgeLifecycleCoordinator` in BridgeLabCore; engine/adapter wiring and independent full-matrix verification remain stage B obligations. This is a technical API extension, not a wire or product behavior change.

No document token or WebKit type enters this package. One executor per adapter, old requests drained on navigation; adapter owns frame trust, wire version/shape, id high-water mark, generation and reply handles. Executor independently validates typed request fields/URL/limits, owns deadlines, redirects, streaming accumulation and task cancellation. Duplicate active id at this layer returns INVALID_REQUEST without replacing the existing task; lifetime monotonicity is adapter responsibility. Package worker may choose internal clock/network delegate injection seams and Swift test framework; keep the public seam stable or report a concrete contract defect for review rather than allowing sibling API guesses.

Use URLSessionDataDelegate chunk callbacks to enforce decoded data bounds. Dedicated ephemeral session, no shared credential/cookie/cache resources. Avoid collecting unlimited data before checking a cap. WKScriptMessageHandlerWithReply gives a Promise return path without eval-based JS interpolation. A weak handler proxy or equivalent ownership strategy avoids WebView/adapter cycles. A serialized generation gate covers navigation races independently from request correlation. Shell shows only a WebView and native Reload button (accessibility id `lab.reload`) plus a generic load failure state, not domain UI.

## Fixed local topology and lifecycle interface

- Web: `http://127.0.0.1:8787/`, serves current `web/dist` assets from disk; no native bundling, no service worker, no persistent cache. Use `Cache-Control: no-store` on all web/API responses. No directory listing or traversal; only files under real resolved web/dist; reject symlink escapes. Missing dist returns 503 diagnostic, never fake demo output. Static assets have correct content types.
- API: `http://127.0.0.1:8788/`; no CORS headers and no auth. Health route `GET /healthz` on both listeners returns JSON `{service:"web"|"api",protocol:1}`. Web readiness does not imply assets exist; lifecycle status reports assets availability separately.
- Default web response CSP: `default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'`. Vite must emit production external JS/CSS compatible with this policy. No inline event handlers/eval or remote dependencies. API access through native remains functional with connect-src none.
- Documented executable entry point: `scripts/lab start`, `scripts/lab status`, `scripts/lab stop`, invoked from any cwd. Derive repo root from the script's own path, not caller cwd. Default state/logs in `<repo>/.artifacts/lab/`. No daemon registration or autostart. Start explicitly backgrounds only owned children and returns after verified listener health, or fails and cleans its partial startup. Stop is required before handoff.
- All three commands accept the same optional `--state-dir <absolute-path> --web-port <port> --api-port <port> --web-root <absolute-path>` for isolated tests. Defaults are fixed above; production iOS policy is not altered by these test flags. Ports must be distinct integers 1–65535; tests allocate temporary loopback ports with bind-conflict retry, never steal a listener. State directories reside in the assigned ignored workspace. Do not expose arbitrary bind host configuration: always 127.0.0.1.
- start: lock state directory to serialize concurrent invocations; verify both ports before spawning; if same live owned configuration is healthy, idempotent success. Foreign/mismatched/partially running state fails safely with actionable diagnostic. Stale files may be removed only after proving no matching owned process; PID alone is never ownership proof. Roll back a partially started owned service if second bind/readiness fails. Readiness deadline 10 seconds; do not equate PID existence with healthy HTTP.
- status: machine-readable JSON to stdout containing `state` (`running`, `stopped`, `stale`, `conflict`), `webPort`, `apiPort`, `assetsAvailable`, and verified owned process identities (PID plus startup identity/canonical script and worktree binding). Errors go to stderr. Exit 0 only for running+healthy, 1 otherwise. Never read/print secret environment data. Start/stop may use succinct diagnostics.
- stop: lock state; verify process start identity and command/worktree match before signals; stop tracked children/listeners, allow 5 seconds graceful shutdown then kill only verified owned children if necessary, reap where parent-owned, verify port release. Idempotent success for already-stopped state; report foreign ownership instead of killing. Do not claim released ports if a foreign process now occupies them. Pending delay sockets/timers are closed. A dedicated supervisor/IPC may be used if needed for reliable ownership; no broad pkill/lsof kill pipelines. Backend tests must prove stale/PID-reuse defense, repeated/concurrent lifecycle and foreign-listener preservation.

## Synthetic fixture contracts (backend/web only)

All JSON is UTF-8 application/json, all text UTF-8 text/plain. Fixtures below are deterministic; no persistence. Echo request `x-lab-tag` only if it meets protocol allowed value rules; logs contain method/path/status/tag and cancellation/connection close, not raw bodies or query values. This tag links UI request and backend evidence, not authentication.

| Route | Request | Response |
| --- | --- | --- |
| GET /api/catalog?category=books | Scenario A; accept application/json | 200 `{"items":[{"sku":"notebook","title":"Notebook"}],"total":1}`; other category gives empty items and total 0 |
| POST /api/quote | Scenario B JSON `{"sku":"notebook","quantity":2}` | 200 `{"quote":{"sku":"notebook","quantity":2,"totalMinor":1200,"currency":"USD"}}`; quantity integer 1–5, unit price 600 minor units; fixed sku only |
| POST /api/quote invalid | Unknown sku, bad shape or quantity outside 1–5 | 422 `{"error":{"code":"INVALID_QUANTITY","message":"Quantity must be 1 to 5"}}` (synthetic single validation error) |
| POST /fixtures/echo | text/plain body | 200 same text/plain body, no JSON decoding |
| GET /fixtures/http-error | none | 503 `{"error":{"code":"UNAVAILABLE","message":"Try later"}}` |
| GET /fixtures/malformed-json | none | 200 application/json literal `{"broken":` |
| GET /fixtures/business-error | none | 200 `{"error":{"code":"OUT_OF_STOCK","message":"Not available"}}` |
| GET /fixtures/delay?ms=1000&label=slow | ms integer 0–30000; label printable ASCII 1–32 chars | Wait ms then 200 `{"label":"slow","delayedMs":1000}`; other valid values echoed; invalid query 400 JSON; close timers when connection closes |
| GET /fixtures/redirect-same | none | 302 Location `/api/catalog?category=books` |
| GET /fixtures/redirect-cross | none | 302 Location `http://127.0.0.1:8787/healthz` |
| GET /fixtures/redirect-loop | none | 307 Location `/fixtures/redirect-loop` |
| GET /fixtures/large?bytes=1048577 | integer 0–1048577 | 200 text/plain ASCII x repeated bytes times, chunked without Content-Length; invalid query 400 |
| GET /fixtures/invalid-utf8 | none | 200 text/plain bytes hex C3 28 |
| GET /fixtures/binary | none | 200 application/octet-stream bytes hex 00 01 |
| GET /fixtures/headers | none | 200 text/plain `headers`, Content-Type text/plain, X-Lab-Tag fixture, Set-Cookie synthetic=1, X-Private synthetic; native exposes only first two |

Unknown route is 404 JSON; wrong method on known route is 405 JSON. Malformed POST JSON is 400 JSON. Backend request-body cap is 65536 bytes, returns 413 on overage and closes/drains safely. No business fixture above is implemented or declared in native production code; native tests may use generic URL paths/data, iOS test bundles may name fixture URLs for acceptance.

## Web variants and acceptance hooks

Web owns `npm --prefix web run build:a` and `build:b` producing the same `web/dist` path using build-time `VITE_LAB_VARIANT=A|B`. Variant A defaults to catalog GET with category query and list rendering; variant B defaults to quote POST with quantity input and nested quote rendering. Each exposes the other scenario via a scenario selector so both remain usable. Build-time variant changes the visible label/default scenario and default request, not only a color/title. A dedicated Diagnostics section offers error/delay/cancel/concurrency exercises through the same bridge client. No automatic call to fetch if WebKit is absent; display bridge unavailable. Mocks exist only in tests, never in shipped assets.

Stable DOM/accessibility hooks: `lab.variant` (A/B), `lab.scenario` selector, `lab.submit`, `lab.cancel`, `lab.loading`, `lab.result`, `lab.error`. Use data-testid for DOM and matching accessible labels where practical. Error display includes category (HTTP, business, JSON parse, transport with code, bridge unavailable), while safe server text is rendered as text, not HTML. Pending requests track their own state; cancel does not blank an unrelated result. Bounded request UI supports a slow and fast request concurrently to prove correlation. iOS UI tests should assert visible web result text rather than treating a test-only native success flag as evidence.

## Same installed binary proof

Integration builds/installs one Simulator app, records exact RC head, installed app container path, executable SHA-256, and a sorted file-hash manifest of the installed .app (excluding nothing unless documented). Build A web assets, start fixtures, launch installed app, submit catalog and capture rendered list plus matching native-executed backend request. Stop/rebuild only web assets to B while keeping installed app unchanged; server may stay up during rebuild because it reads from disk, but reload only after completed build. Hash web assets before/after. Tap native Reload, see B marker, submit quote, capture nested total and endpoint change. Do not run xcodebuild, simctl install, or alter native launch configuration between observations. Rehash installed executable and bundle after B; hashes must match A. Record command transcript proving no reinstall/rebuild. Business source audit includes ios production and TransportPackage sources, excluding tests. Actual WKWebView end-to-end evidence, not plain browser mocks, is mandatory.

Dedicated project Simulator and fixed ports are serialized in integration/acceptance. Earlier module tests use injected transport/fake message frames/temporary fixture resources; iOS compilation and bridge unit tests do not require a shared live backend. Simulator acceptance shuts down its owned session and all services, records released ports and leaves unrelated processes/Simulators untouched. Reproducibility commands implemented later must fail on missing tools instead of fabricating successful output.

## Deliberate limits and risk decisions

Plain HTTP is allowed solely for fixed loopback Simulator origins, using minimal local-network/ATS development configuration in ios; do not use a global arbitrary-load entitlement as API policy. Real devices, production trust bootstrapping, auth/cookies, arbitrary external endpoints, binary/streaming/file APIs, retries/cache platform and cloud deployment remain out of scope. Trusted web code possesses the bounded HTTP capability for all paths on the allowed API origin; CSP is not a substitute for reviewing that code. Cancellation stops local network work but cannot undo server effects. Schema validation cannot prove WebKit provenance or URLSession behavior. The first acceptance is a reusable foundation, not a production security claim.
