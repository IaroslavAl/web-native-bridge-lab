## 1. Foundation and independent specification review

- [ ] 1.1 Validate proposal/design/delta specs plus v1 schema and labeled examples using pinned local tooling; retain exact command evidence.
- [ ] 1.2 Independently review protocol/security/module decisions and test matrix on the foundation card; approve exact head before releasing consumers.

## 2. Backend and local lifecycle (backend card)

- [ ] 2.1 TDD deterministic synthetic API/error/delay/redirect/size fixtures and safe static serving under backend/.
- [ ] 2.2 Implement scripts/lab start/status/stop with ownership, readiness, conflict, stale-state and child-cleanup tests on isolated resources.
- [ ] 2.3 Run backend gates, stop owned services, commit and obtain independent same-card review.

## 3. Generic native transport (transport card)

- [ ] 3.1 TDD the architecture Swift seam: request validation, GET/POST opaque bodies, HTTP versus transport outcomes.
- [ ] 3.2 TDD exact origins/headers/redirect/credential behavior, decoded byte bounds, timeout/cancel/late callback and concurrent correlation.
- [ ] 3.3 Run swift package tests, preserve command evidence and obtain independent same-card review of exact head.

## 4. WKWebView app and adapter (iOS card)

- [ ] 4.1 Merge reviewed transport/foundation heads and implement wire version/shape, trusted main frame, generation and safe reply handling.
- [ ] 4.2 Test navigation/reload/close/process-termination revocation, id ordering, unsupported messages and teardown ownership.
- [ ] 4.3 Compile actual Simulator app and run bridge tests; preserve project/build commands and obtain independent same-card review.

## 5. React/TypeScript client and web scenarios (web card)

- [ ] 5.1 TDD Promise correlation, cancellation, missing bridge and malformed replies with explicitly labeled native mocks.
- [ ] 5.2 Implement catalog GET and quote POST, web-owned query/headers/body/JSON/error UI, diagnostics and build:a/build:b hooks.
- [ ] 5.3 Pin dependencies, build real web/dist assets, run web gates and obtain independent same-card review.

## 6. Integrated RC and same-binary evidence (integration card)

- [ ] 6.1 Merge all reviewed module heads preserving identities; implement scripts/verify and top-level reproducibility instructions.
- [ ] 6.2 Run unit/build/schema/lifecycle suites and actual WKWebView catalog A → web-only build B → quote acceptance with unchanged installed executable/bundle hashes.
- [ ] 6.3 Exercise real error/JSON/timeout/cancel/concurrency/origin/iframe/redirect/navigation/size gates and preserve durable evidence, not just temporary log paths.
- [ ] 6.4 Stop owned servers/Simulator session, verify released ports/foreign-process preservation and request independent same-card RC review.

## 7. Independent product acceptance and closure

- [ ] 7.1 Independent verifier repeats exact-RC real Simulator/security/lifecycle/same-binary gates and reports passed/failed/skipped plus limits.
- [ ] 7.2 Delivery synthesis reconciles source/spec/tests/graph and reports accepted head, agent-flow evidence and safe coordinator next steps.
- [ ] 7.3 Coordinator performs authorized canonical spec sync/archive only after required gates, final main/cleanup and owner RC handoff; no publication implied.

All tasks are intentionally unchecked in the proposed foundation. Later completion must cite command-backed evidence and exact reviewed head, not merely existence of an artifact or a green document parser. Module workers avoid this shared file; integration/coordinator reconcile checkboxes from reviewed handoffs.
