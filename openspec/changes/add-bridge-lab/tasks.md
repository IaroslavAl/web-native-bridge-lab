## 1. Foundation and independent specification review

- [x] 1.1 Validate proposal/design/delta specs plus v1 schema and labeled examples using pinned local tooling; retain exact command evidence.
- [x] 1.2 Independently review protocol/security/module decisions and test matrix on the foundation card; approve exact head before releasing consumers.

## 2. Backend and local lifecycle (backend card)

- [x] 2.1 TDD deterministic synthetic API/error/delay/redirect/size fixtures and safe static serving under backend/.
- [x] 2.2 Implement scripts/lab start/status/stop with ownership, readiness, conflict, stale-state and child-cleanup tests on isolated resources.
- [x] 2.3 Run backend gates, stop owned services, commit and obtain independent same-card review.

## 3. Generic native transport (transport card)

- [x] 3.1 TDD the architecture Swift seam: request validation, GET/POST opaque bodies, HTTP versus transport outcomes.
- [x] 3.2 TDD exact origins/headers/redirect/credential behavior, decoded byte bounds, timeout/cancel/late callback and concurrent correlation.
- [x] 3.3 Run swift package tests, preserve command evidence and obtain independent same-card review of exact head.

## 4. WKWebView app and adapter (iOS card)

- [x] 4.1 Merge reviewed transport/foundation heads and implement wire version/shape, trusted main frame, generation and safe reply handling.
- [x] 4.2 Test navigation/reload/close/process-termination revocation, id ordering, unsupported messages and teardown ownership.
- [x] 4.3 Compile actual Simulator app and run bridge tests; preserve project/build commands and obtain independent same-card review.

## 5. React/TypeScript client and web scenarios (web card)

- [x] 5.1 TDD Promise correlation, cancellation, missing bridge and malformed replies with explicitly labeled native mocks.
- [x] 5.2 Implement catalog GET and quote POST, web-owned query/headers/body/JSON/error UI, diagnostics and build:a/build:b hooks.
- [x] 5.3 Pin dependencies, build real web/dist assets, run web gates and obtain independent same-card review.

## 6. Integrated RC and same-binary evidence (integration card)

- [x] 6.1 Merge all reviewed module heads preserving identities; implement scripts/verify and top-level reproducibility instructions. Stage1 checkpoint evidence: docs/integration/STAGE1.md; the full implemented cross-layer command set is now mapped in docs/integration/FINAL_MATRIX.md.
- [x] 6.2 Run unit/build/schema/lifecycle suites and actual WKWebView catalog A → web-only build B → quote acceptance with unchanged installed executable/bundle hashes. Stage1 actual Simulator42 + UI1 PASS, clean three-file installed shell unchanged; docs/integration/stage1-evidence.json. This is implementation evidence, not independent final acceptance.
- [ ] 6.3 Exercise real error/JSON/timeout/cancel/concurrency/origin/iframe/redirect/navigation/size gates and preserve durable evidence, not just temporary log paths. Stage2 outcome slice implements `scripts/verify simulator-stage2-outcomes` for real HTTP503/422/business/JSON/native timeout/explicit cancel/concurrency/backend-off errors; see docs/integration/STAGE2_OUTCOMES.md. Stage1–5 and final supplemental vectors are reconciled in docs/integration/FINAL_MATRIX.md. This checkbox remains open until the final-source regression record is retained; historical stage-pending statements below describe their checkpoint, not missing implemented modes.
- [ ] 6.4 Stop owned servers/Simulator session, verify released ports/foreign-process preservation and request independent same-card RC review.

Stage3 bounded evidence: `scripts/verify simulator-stage3-trust-limits` adds actual installed-shell raw wire/session/id, origin URL/header policy, same/cross/loop redirect zero-destination-hit, Unicode/raw/chunked/media limits and8/ninth BUSY probes. See docs/integration/STAGE3_TRUST_LIMITS.md for exact layer distinctions and gaps. CSP-denied iframe loading is NOT real iframe handler-provenance proof. Task6.3 and independent review/acceptance remain unchecked.

Stage4 component evidence: `scripts/verify simulator-stage4-webkit-privacy` runs actual WebKit frame provenance (test-only outer navigation bypass, no production CSP relaxation), navigation/reload/provisional failure/close/destruction with real socket cancellation, fresh-id isolation and synthetic native/WK cookie/cache/challenge isolation. See docs/integration/STAGE4_WEBKIT_PRIVACY.md for observed layers, mutation checks and irreducible/deferred gaps. No installed-React or actual OS process-termination claim;6.3 remains unchecked.

Stage5 bounded evidence: `scripts/verify simulator-stage5-production-ux` exercises the real production Diagnostics UI after same-installed-app A/B; `python3 scripts/tests/operations.py` exercises owned SIGINT/SIGTERM/command-failure cleanup and synthetic foreign-port preservation. Existing slow diagnostic now allows10s for cancellation (15s native deadline); no new product controls or policy changes. See docs/integration/STAGE5_UX_OPERATIONS.md and its observed evidence JSON for actual test layers, discovered runner fixes and explicit interruption limits. Final source regression/reconciliation and independent review are still required;6.3/6.4 remain unchecked.

## 7. Independent product acceptance and closure

- [ ] 7.1 Independent verifier repeats exact-RC real Simulator/security/lifecycle/same-binary gates and reports passed/failed/skipped plus limits.
- [ ] 7.2 Delivery synthesis reconciles source/spec/tests/graph and reports accepted head, agent-flow evidence and safe coordinator next steps.
- [ ] 7.3 Coordinator performs authorized canonical spec sync/archive only after required gates, final main/cleanup and owner RC handoff; no publication implied.

Upstream checklist reconciled from independently approved parent handoffs: foundation e9f3381, transport b5c5423 (plus iOS-reviewed admission extension), backend4e4474f, iOS15a9b53 and web6936e00. Full SHAs, actual tests and proof-layer limits are in docs/integration/FINAL_MATRIX.md and parent Kanban completion metadata. Historical RED chronology remains attributed module evidence, not a claim it was independently replayed in this final run. Integration final-source gates and independent review/acceptance remain separate. Completion must cite command-backed evidence and exact reviewed head, not merely existence of an artifact or a green document parser. Module workers avoid this shared file; integration/coordinator reconcile checkboxes from reviewed handoffs.
