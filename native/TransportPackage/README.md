# TransportPackage — PER-85 review candidate

Foundation-only generic HTTP executor. No WebKit, UIKit, business endpoint registry or domain JSON decoder. Normative contract: `../../protocol/v1/README.md` from repository root (see `docs/architecture.md` for the cross-module seam). The reviewed foundation commit is `e9f338142735b754362c59ed62ad1fa8450c0b4e`; no contract changes in this package.

## Use and ownership

Link Swift package product/module `TransportPackage` (iOS 17+, macOS 13+; tools 5.9). The public `HTTPRequest`, `HTTPResponse`, `TransportFailure`, `HTTPResult`, `TransportPolicy` and actor `HTTPExecutor` match the architecture seam. All public values have explicit initializers and are Sendable. Initialize one executor per adapter with native-owned `TransportPolicy(allowedOrigin: URL(string: "http://127.0.0.1:8788")!)`.

Call `await executor.execute(request)` for a response or sanitized failure. HTTP 4xx/5xx and nonredirect 304 remain responses. Interpret business JSON only in React. Use `await executor.cancel(id:)` and `await executor.cancelAll()`; cancelling the surrounding Swift Task is not the explicit transport cancellation API. The adapter must await cancelAll on document revocation before admitting new work, and separately enforce frame/origin, wire shape/version/session, message cap, ID monotonicity and reply-generation binding. Those are deliberately not TransportPackage responsibilities.

GET/POST, complete URL/query, header and body semantics are validated before network creation. All five redirect statuses are rejected, including same-origin targets; no revalidated destination is followed. Dedicated ephemeral URLSession per accepted execution has nil credential/cookie/cache stores, does not accept cookies, and cancels authentication challenges. All unexposed server headers are omitted from results.

## Ingestion and lifetime safety

- `NetworkEventRelay` synchronizes cumulative decoded Data byte accounting on the producer callback BEFORE enqueueing a chunk. At most 1,048,576 payload bytes across queued/consumed events are admitted per execution. The first excess chunk is not retained: it produces an explicit RESPONSE_TOO_LARGE event and synchronous underlying cancellation. Later input is rejected, not silently converted into a truncated success. Empty chunks consume no queue nodes. Each nonempty chunk consumes at least one of the bounded admitted bytes, bounding Data event count as well. Actor accumulation independently checks the same cap.
- Cancellation is outside the relay lock, avoiding delegate reentrancy deadlock. The relay's reference to its task is weak. Attaching a task after a synchronous creation-time overflow still cancels it.
- Each admission owns a native UUID unrelated to the public integer ID. BOTH deadline and network actor entry check it. Already queued actor hops cannot resolve/cancel a new execution reusing the same integer after cancelAll. Closing a relay also rejects later producer callbacks.
- The actor serializes terminal decisions; removing state precedes continuation resolution. Deadlines/consumers are cancelled and relays closed on every terminal path. Monotonic Task.sleep is independent of URLSession's inactivity timer.

## Reproduce local gates

From repository root:

    swift test --package-path native/TransportPackage -Xswiftc -warnings-as-errors
    swift build --package-path native/TransportPackage -c release -Xswiftc -warnings-as-errors
    git diff --cached --check

No external dependencies or test services. The shared semantic-vector test reads `protocol/v1/examples.json` relative to its source location, so run tests in the full repository, not a copied standalone package.

## Durable implementation evidence (2026-09-08)

Environment actually observed: Apple Swift 6.3.3, arm64-apple-macosx26.0. Worktree `t_b5a1054d`, branch `web-native-bridge-lab/t_b5a1054d-per-85-transport-implementer`. Recovery routing checked in board record: gpt-6-astra / openai-codex / high. Original timed-out implementation was preserved, not re-scaffolded. Coordinator reported its 27 passing tests; this run independently exercised the preserved suite plus regressions.

1. RED: warnings-as-errors `--filter IngestionRegressionTests` returned exit 1: expected synchronous cancellation at byte 1048577, observed nil while actor consumer could not run. This reproduced the unbounded pre-actor queue defect, not a speculative OS-buffer concern.
2. GREEN after synchronized cap: full suite 28 tests, zero failures, exit 0.
3. RED: `--filter DeadlineTests.testAlreadyFiredOldDeadline` returned exit 1 with two assertions: replacement task was cancelled and replacement result was TIMEOUT rather than HTTP204. The async scheduler seam allows deterministic waiting for the stale callback's actor hop even after token cancellation; no sleep-based ordering assumption.
4. GREEN after execution UUID gates: full suite 31 tests, zero failures, exit 0.
5. Added conformance verification of existing behavior: exact URL/body/header bounds and +1, timeout endpoints using inert scheduler, JSON POST bytes, HTTP200/304/422/503, repeated exposed headers, six shared transport semantic vectors. Final warnings-as-errors run: 35 XCTest tests, zero failures, zero skips, exit 0 (2026-09-08 10:41:33 host test log). Release build also exit 0. The separate Swift Testing runner reports zero tests because this package uses XCTest; that is not the XCTest total.
6. `git diff --cached --check`: exit 0. Scoped source scan found no TODO/FIXME/debug print, `/api/`, business JSON decoder, shared URLSession/cookie/credential access or SecItem calls. Full sources and tests were read for self-review; independent same-card review remains required.

Raw logs during this run: `.artifacts/transport/{ingestion-red,ingestion-green,lifetime-red,lifetime-green,final-tests,release-build}.log`. They are disposable; the results and failure diagnoses above plus the card handoff are the durable evidence. Do not treat temporary paths as retained artifacts after worktree cleanup.

## Coverage and remaining integration obligations

| Requirement | Actual executable evidence | Not established here |
| --- | --- | --- |
| HT-01 | HTTPExecutorTests, RequestValidationTests, ContractBoundaryTests preserve GET query/headers and opaque POST UTF-8/JSON | Real Simulator catalog/quote, native network provenance |
| HT-02 | malformed JSON unchanged; HTTP200/304/422/503; empty204; injected network failure | Real connection refusal and UI classification |
| HT-03 | invalid URL/header/host vectors start zero fake tasks; all redirect statuses denied; redirect delegate returns nil | Socket-level redirect destination hit count zero, malformed/missing Location behavior through Foundation |
| HT-04 | nil session stores/cache, cookies disabled; response header filtering; manually invoked auth delegate cancels with nil credential | Populated synthetic ambient stores and real HTTP auth/cookie exchange; no actual credentials accessed here |
| HT-05 | exact/+1 bounds, Unicode bytes, invalid UTF-8/media, 8/9 concurrency, injected/real monotonic deadlines, deterministic producer-ahead byte cancellation and retained-queue cap | Actual chunked/gzip decoded overflow and slow-trickle server connection closure |
| HT-06 | cancel/response/deadline precedence, late callbacks, duplicates, out-of-order correlation, cancelAll/reused-ID stale deadline regression | Actual WKWebView revocation and URLSession/server cancellation observation |

Most tests use explicit HTTPNetworkClient doubles. `URLSessionNetworkClientTests.testURLSessionTaskStreamsResponseAndBody` exercises real URLSession delegate dispatch but uses a custom URLProtocol, not an HTTP socket. Redirect and authentication tests invoke real delegate implementations manually. Do not relabel these as wire-level/Simulator proof. No loopback listeners, child services, Simulator, signing, publication or other modules were started/changed by this run. Integration and independent acceptance must execute the real-network obligations above before mission acceptance.

Framework header/decompression internals and total process RSS are not bounded/measured by the application's decoded-data cap. Bounded Data queue node overhead, actor accumulation and final UTF-8 String allocation also mean this is not a 1MiB total-memory promise. HTTPNetworkClient is an internal trusted injection seam, not an arbitrary wire capability. Local synthetic HTTP and Simulator only; not production-ready.

Downstream must merge the exact independently approved transport head from this card, preserving foundation ancestry. Do not consume an unreviewed worktree or infer availability from main. iOS child `t_b5aeb77f` is implementation, not a substitute for this card's mandatory iosverifier review. No archive or final product acceptance is claimed here.
