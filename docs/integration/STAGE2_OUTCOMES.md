# Stage2 — bounded real outcome slice, not a release candidate

Status: implementation checkpoint only. Stage1 coordinator acceptance remains scoped to `cca954dd65f801d6c2b531208ab97c2281be2509`. This extension requires coordinator inspection and the eventual independent same-card integration review; full security/lifecycle acceptance is still pending. No production native, backend, client, interpreter or App source was changed.

## Reproduction and evidence ownership

Run `scripts/verify unit`, then `scripts/verify simulator-stage2-outcomes` from this worktree. Ports 8787/8788 must be free. The command creates and removes its own Simulator, repeats all existing Simulator tests and the real production React catalog A → quote B same-installed-app proof, then loads a separately built opt-in React test page. Test-only `web/acceptance/` imports the unchanged production `BridgeClient` and response interpreters. It is not included by either normal A/B build. No JS evaluation, native fake executor, browser network fallback, native test endpoint or policy expansion is used.

`SameBinaryTests.testWebOnlyUpdateOnSameInstalledApplication` asserts the actual accessibility tree in the installed app. The test runner only uses the static web port for coordination. The production backend's CSP still forbids browser connections. A third web-only payload replacement and Reload bring in the outcome probes; native executable/container/full file manifest remain unchanged across A/B and these probes. This is installed-shell, real WebKit/native URLSession/backend evidence, NOT the production Diagnostics UI layout or accessibility proof. Existing Simulator adapter tests include injected seams and are labeled separately.

Durable sanitized results are in `stage2-outcomes-evidence.json`: tested source head, exact commands/exit codes, suite summaries, installed manifests, web hashes, backend events, actual UI attachment text, cleanup and tool versions. The evidence-only commit necessarily follows the tested source head. Raw `.artifacts/verify-*` paths are disposable and not the only retained proof. No final acceptance or OpenSpec archive is implied by passing these gates.

## Requirement → observed scenario → actual assertion

| Requirement/scenario | Real installed-shell assertion and corroboration | Scope |
| --- | --- | --- |
| HT-01 / WS-01 / WS-03 | Production App catalog GET then quote POST, real visible business results; changed served hashes, identical complete clean installed bundle | Stage1 regression repeated |
| HT-02 / T-OUTCOME | HTTP503 and HTTP422 exact status/body retained; production interpreters throw HTTP category with original body | Test React page, real native/backend |
| WS-02 / T-UX | HTTP200 business error classified OUT_OF_STOCK; malformed JSON status200/body `{"broken":` preserved and classified JSON parse | Production interpreters, test React rendering; not production App diagnostics |
| HT-05 / T-BOUNDS deadline subset | Request deadline500ms versus delay2000ms produces native TIMEOUT, no JS timeout race | Backend must record exactly one tagged connection-close, no success |
| HT-06 / T-RACES cancel subset | Explicit cancel returns true and original request throws correlated CANCELLED; repeated completed cancel returns false | Backend must record exactly one tagged connection-close, no success |
| HT-06 / WB-03 / T-CORRELATION | Concurrent slow1500ms / fast10ms requests have distinct IDs; each reply matches ID/tag/body and completion order is fast then slow | Both React assertions and ordered backend events |
| HT-02 network failure | Host actually stops the owned backend, verifies free ports and stopped status, then loaded React submits another native request | NETWORK_ERROR required; UI runner never calls API |
| LL-02 cleanup subset | Start/status/stop plus already-stopped stop; port rebind and own Simulator absence | Normal run and explicit backend-off path; adversarial signal cases still pending |

The page waits beyond the cancelled fixtures' original completion times before declaring the matrix complete. The host rejects missing/duplicate tagged events or any later success for timeout/cancel. The verifier helper was introduced RED (missing `require_stage2_events` assertion), then GREEN with exact positive/missing/reordered/duplicate/late-success vectors. New code is test infrastructure only; no product implementation was added to make outcome checks pass.

## Explicit remaining integrated gaps — not waived

- HT-01: real installed-shell exact POST text/query edge cases beyond production A/B.
- HT-02: real empty204 response.
- HT-03: actual redirect same/cross/loop denial with destination zero hits, alternative origin and malformed URL/header probes.
- HT-04: isolated synthetic sentinel cookie/credential/cache and challenge probes; no real credential stores may be inspected.
- HT-05: request/raw/response/header byte boundaries, Unicode, chunked/compressed/encoding/media cases, 8 accepted / 9th BUSY, slow-trickle native deadline. This slice covers only the ordinary delayed timeout.
- WB-01: actual WebKit malformed/version/session/raw-message inputs; schema and adapter doubles are not sufficient provenance proof.
- WB-02: real same-origin iframe / foreign-origin metadata, precommit/inactive state and forbidden navigation/new-window behavior.
- WB-03/WB-04: hostile text serialization without execution/navigation; live slow request reload/navigation/close with old completion isolation and new document ID reuse; queued stale token and teardown under actual WebKit.
- WS-02: production Diagnostics UI error/loading/cancel-isolation and safe rendering paths beyond test-page interpreter probes.
- LL-02: adversarial integration-runner SIGINT/SIGTERM/interruption, owned children/no-orphan traces, foreign occupied fixed-port preservation. Backend process suites exercise isolated lifecycle cases but do not substitute for these runner checks.
- LL-03: complete matrix reconciliation, independent integration review, independent exact-RC acceptance, owner RC handoff. No generic full `simulator` gate is advertised yet.

## Limits and routing

Simulator only; synthetic loopback HTTP; no production security claim, real-device test, publication, credentials or server-side rollback guarantee. URLSession/OS buffering is not bounded by application tests. Native timeout is observed as an actual native TIMEOUT plus server socket close; this is not a precision latency benchmark. An XCUI control request connection-refused log is expected after deliberate service shutdown. Xcode may emit AppIntents/XCTest build warnings; no warnings-free Xcode claim.

Binding checks: task `t_9d8fd391`, board `web-native-bridge-lab`, declared project `p_ce173eae`, own worktree/branch/common Git directory verified. Card override and session identify `openai-codex/gpt-6-astra`; coordinator packet pins high effort. Effective effort is not independently exposed by these tools. No model/profile/runtime edits, primary-main update, graph changes or child agents were made.

At this bounded checkpoint the coordinator schedules the same card using the `PER85_COORDINATOR_CHECKPOINT` protocol. Resume from the exact checkpoint head and the remaining list above; do not treat passing outcomes as completion of task6.3 or release final acceptance. The pre-created acceptance child remains scheduled and its hold was not altered.
