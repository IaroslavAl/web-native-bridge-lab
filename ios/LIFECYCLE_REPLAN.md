# iOS lifecycle replan — coordinator design acceptance required

Design only for `t_b5aeb77f`; not an implementation, approval, spec amendment, or release. The coordinator's `per85-ios-lifecycle-replan.md` packet supersedes IMPLEMENT NOW for this run. Original acceptance remains unmet. No further patch loop until the coordinator accepts the ordering model below.

## 1. Inspected baseline and evidence boundary

- Workspace: `/Users/agent/hermes-clean-20260903/projects/web-native-bridge-lab/.worktrees/t_b5aeb77f`.
- Branch: `web-native-bridge-lab/t_b5aeb77f-per-85-ios-bridge-implementer`.
- Baseline HEAD: `3f5422db00e23b66910cbdd2941a5c645ac521f1`, NOT approved. Both approved parents are already ancestors: transport `b5c5423c585b8599f5639075e5c40c8a5f517ada`, foundation `e9f338142735b754362c59ed62ad1fa8450c0b4e`; no merge needed.
- Preserved run63 dirty path: `ios/Tests/BridgeLabCoreTests/WKBridgeAdapterTests.swift`. SHA-256 at entry: `7e6b53bbe6db2a3b698936d2b5cf34b62e934842e115cb59e110682dfcc0d73b`. Contains two added first-terminal tests and a change enabling cancellation in the late-success test. These edits are neither accepted nor modified by this design run.
- Read original task, parent completion metadata, reviewer comments 94/97/100, source/tests, `AGENTS.md`, owner mission, protocol, architecture and WB/HT specs. `git diff --check` and exact parent ancestry checks passed. Live worker PID 97993 argv confirms `deliverylead`, `openai-codex`, `gpt-6-astra`, `--reasoning high`; board/workspace environment and Git common-dir match this project. Project ID `p_ce173eae` is the task's declared binding; the show response/environment did not independently expose its project association.
- No runtime tests, builds, Simulator or backend operations performed in this planning run. Historical green suites and reviewer reproduction are attributed evidence, not fresh verification. Only this note is authored here.

## 2. Diagnosis: three different clocks were treated as one

Source references below refer to baseline HEAD, except explicitly identified dirty tests.

1. MainActor document invalidation: `WKBridgeAdapter.swift:74-87` increments lifecycleID and asynchronously chains `engine.revokeDocument()`.
2. Native terminal selection: `HTTPExecutor` in `native/TransportPackage/Sources/TransportPackage/TransportPackage.swift:300-384` serializes network/deadline/cancel decisions. Removal from `active` at line 364 or 378 makes the result irrevocable, cancels the deadline and resumes the result continuation. `cancelAll` at lines 289-292 can only cancel entries still active.
3. WebKit publication: `BridgeEngine.swift:173-178` converts that selected result, then `WKBridgeAdapter.swift:152-200` later runs on MainActor and guesses a different outcome from current lifecycleID and result shape.

The defect is the second terminal arbiter at publication, not missing error-code cases. `ReplyOnce` prevents two callback calls but cannot repair a wrong first value. Generation mismatch proves that an invocation is old; it does NOT prove cancellation won against its native task.

### Finding disposition

| Evidence | Classification / consequence |
| --- | --- |
| R1 queued invocation was not bound across suspension; adapter tests absent | Confirmed historical defect. R2 added partial protection and tests. Keep generation binding; do not revert it to fix terminal outcomes. |
| R2 production cancelAll result became ORIGIN_DENIED/null | Confirmed contract defect, statically traceable to the post-generation mapping. R3 special-cased it but left the design flaw. |
| R3 preselected NETWORK_ERROR became ORIGIN_DENIED/null | Confirmed invalid mapping if executor selection has happened. Reviewer reported an isolated failing Simulator reproduction; not rerun here. All selected responses AND failures must remain immutable. |
| Reviewer recipe `await executor.resolve(); reload()` | `resolve` removes/resumes the fake pending continuation before returning, so it represents terminal selection in that fake. It does NOT guarantee MainActor publication is still pending; scheduler order makes reproduction frequency variable. A URLSession callback merely emitted into the relay is NOT equivalent to an executor-selected terminal result. |
| Old success after a fake cancelAll which only counts calls | Not evidence that production cancelAll permits success after cancellation won. This fake violates the required cancellation boundary. It can test a deliberately nonconforming executor only if labelled as such, not define production arbitration. |
| Dirty run63 late-success test now enables cancelPendingRequests | Its later `resolve` finds no pending continuation; no late event reaches the production executor. This is cancellation coverage, not adequate late-network coverage. Preserve it now; replace its claimed evidence with a real lower-layer late-event test during implementation. |
| Source-level admission gap | Additional risk, not a newly reproduced failure: current `engine.handle` suspends on `executor.execute`, and revoke can run while that actor hop is outstanding. `cancelAll` is not a barrier against a request that has not entered the executor yet. Task creation order is not a FIFO guarantee. |
| Proxy boundary at `WKBridgeAdapter.swift:267-269` | Additional source-level risk: it inserts a Task before native generation capture. Capture provenance/generation at the actual delegate callback, not a later proxy task. Local SDK `WKScriptMessageHandlerWithReply.h:38,91` marks protocol and reply handler `WK_SWIFT_UI_ACTOR`; use compiler-checked MainActor isolation, not an unchecked thread assumption. |

## 3. Recommended decision: one terminal owner, separate ingress and publication

Preserve HTTPExecutor as the ONLY arbiter for admitted HTTP work, as required by HT-06. Introduce an explicit FIFO lifecycle/admission coordinator in iOS; it sequences short control operations, not entire HTTP lifetimes. Do not add a second response-vs-cancellation race in the adapter.

### Linearization points

- **Ingress revocation fence:** synchronous MainActor invalidation of generation `g` at an allowed navigation/reload/failure/termination/close callback. Later ingress and still-queued old invocations cannot be admitted. Rejected navigation changes nothing.
- **HTTP admission:** executor actor installs active task, deadline and execution identity without suspension. Semantic rejection/BUSY returns an immediate immutable result instead. HTTP capacity is never queued waiting for a slot.
- **FIRST TERMINAL:** executor actor removes the matching active execution and fixes its HTTPResult. Success, transport failure, native deadline, explicit cancel and cancelAll compete here, not at a later MainActor callback. Event emission, task launch and wall-clock timestamps are not terminal selection.
- **Publication:** the immutable selected result is converted once and passed to its captured originating WebKit reply handle on MainActor. Publication does not look up the current page/request by integer id, and does not rewrite the selected result based on current generation.
- **Drain complete:** prior admission/control operations have finished, cancelAll has run, and every admitted old invocation's result/publication task has settled or retired its original reply and released its record. Only then may the next trusted committed generation accept hello/request/cancel.

There is an overlap interval between the synchronous ingress fence and execution of cancelAll on the executor. A native terminal selected in that interval may win; this is NOT late delivery into a fresh document. It is settlement of the old Promise by the one native decision owner. New work remains fenced immediately. A result selected before cancelAll cannot be replaced with CANCELLED; a completion offered after cancelAll removed the execution cannot become a response.

**Coordinator decision required before implementation:** accept this executor-linearized interpretation, consistent with protocol lines 76/78 and HT-06, plus the additive admission receipt below. If “navigation callback entry itself must beat every as-yet-unselected network event” is intended, choose the alternative shared synchronous arbiter in section 7 and replan its cost. Do not resolve that stronger ordering by changing assertions or rewriting the normative spec silently. This is a coordinator engineering clarification, not a new owner question.

### Document and invocation states

Proposed names below are design APIs, NOT existing symbols.

- `DocumentState`: inactive; activating(g); active(g, session, highWaterMark); revoking(g); closed. Native generation is independent of the wire session. Keep retired contexts separate from the prospective new context, never mutate a shared context into a new generation.
- `InvocationKey`: native `(generation, invocationNonce)`, never integer id alone. The nonce distinguishes hello, cancel, malformed and duplicate invocations. Parsed request id remains correlation data.
- `InvocationState`: queued -> immediateReply OR admitted(execution receipt) -> terminalSelected(result) -> publishedOrRetired. Queued old invocations invalidated before admission receive ORIGIN_DENIED/null without parsing, as protocol line 25 requires. Validated immediate results retain their already-selected id/code.
- `HTTPExecution`: immutable per-execution identity plus a one-result awaitable. It must retain an already-selected result if no waiter is registered yet and release it after its owner is finished. Do not introduce an unbounded completed-id history.

### Control sequencing and ownership

1. `WKBridgeAdapter`/weak message proxy remains MainActor-isolated. At the real WebKit callback, synchronously capture generation, active/trusted main-frame provenance, bounded raw input and a one-shot reply holder. No extra Task before capture. The direct unit seam must exercise the same ingress path, not bypass its token capture.
2. One MainActor `BridgeLifecycleCoordinator` appends ordered commands for ingress, activation, explicit cancel and revocation. A single consumer awaits each SHORT admission/control operation to completion before dequeuing the next. Reentrancy may append commands but never run a second consumer. Do not rely on independent Task scheduling order.
3. Refactor engine handling into validation/session/id consumption plus a submission result: immediate BridgeReply, or an admitted execution receipt. The consumer must await acknowledgement of executor admission, not the eventual HTTP response. Then record a separate result/publication task and continue with subsequent admissions/cancels. This preserves eight concurrent requests and out-of-order completion. The ninth gets BUSY at admission, not later capacity-based retry.
4. If revocation occurs before a queued invocation begins admission, reject it. If admission is already in flight, order revocation AFTER its receipt; therefore cancelAll cannot miss it. That overlapping admission either returns an immediate result or participates in the executor's first-terminal decision. Fence all later old work. Never await an HTTP lifetime in the admission consumer, which would make cancel/reload wait for its own request.
5. Revoke invalidates engine session/high-water state, awaits executor.cancelAll, then joins old publication tasks. Result workers do not wait on this command queue, avoiding a drain deadlock. Do not hold an engine actor/lock while waiting for work that needs it. An old queued cancel cannot target fresh id 1: it is rejected before admission; an admitted cancel completes before the drain barrier. Repeated revoke/close is idempotent for the same retiring context.
6. Physical didCommit may arrive during drain. Record activation intent for its native generation; do not grant capability until old drain completes and that intent is still current. Multiple reloads invalidate superseded intents. Trusted new hello may wait for its own activation; it must never adopt another generation's session. Untrusted/pre-commit ingress stays denied.
7. Pending workers retain only their old context/receipt/reply holder, not adapter or WebView. Adapter owns registration and weak WebView link; userContentController owns a weak-delegate proxy. Explicit close immediately removes handler/delegate, closes ingress and initiates the ordered drain. Destruction fallback hands cleanup to the retained coordinator without capturing the dying adapter, using compiler-checked actor isolation. It must also close/fence queued ingress before that ingress can run. Test this fallback separately, not merely close-then-deinit.
8. `ReplyOnce` is only the delivery gate. Clear its stored callback on first use; take it under isolation/lock and invoke outside the lock on MainActor. A WebKit-discarded old Promise counts as retired, not permission to evaluate JavaScript in the new document. Release reply records after use. Cleanup tasks may retain the coordinator only until draining; do not leave a permanent self-retaining consumer.

## 4. Concrete minimal change surface after approval

| Location | Bounded change |
| --- | --- |
| `native/TransportPackage/Sources/TransportPackage/TransportPackage.swift` | Add `submit(_:) async -> HTTPSubmission`, with cases `immediate(HTTPResult)` and `running(HTTPExecution)`. Submission returns after semantic validation/admission, without awaiting HTTP completion. The Sendable receipt exposes `result() async -> HTTPResult`; only the executor may select its value. Preserve public `execute` as a compatibility wrapper awaiting the receipt. Keep active execution UUID, relay, caps, URL/header policies, deadlines, cancel/cancelAll and terminal selection in the executor. No WebKit, document/session token or business type enters this package. |
| `ios/Sources/BridgeLabCore/BridgeEngine.swift` | Adapt HTTPExecuting seam and separate short admission from result conversion. Keep validation precedence, session checks and id consumption. Generation validation and ordered revoke/activate must use the coordinator's captured context; not a late current-engine lookup. |
| New `ios/Sources/BridgeLabApp/BridgeLifecycleCoordinator.swift` | Only ordered lifecycle/admission, retired-context ownership and drain bookkeeping described above. Typed BridgeReply/HTTPResult crosses tasks, not untyped WebKit dictionaries. |
| `ios/Sources/BridgeLabApp/WKBridgeAdapter.swift` | MainActor ingress capture before suspension, thin event forwarding and reply holder cleanup. Delete `replyForRetiredInvocation` outcome guessing. Preserve page policy and originating reply serialization. |
| `ios/Sources/BridgeLabApp/BridgeScreen.swift` | Only if needed to wire coordinator/explicit lifetime cleanup; no UI/product changes. |
| Scoped iOS/transport tests, iOS Xcode project, `ios/README.md` | Add/register coordinator tests, deterministic barriers, coverage/evidence. No dependency install or generator required. |

The stable public seam currently promises only execute/cancel/cancelAll (`docs/architecture.md:25-34`). The admission receipt is an additive technical extension requiring coordinator design approval and independent native regression review, not a worker's incidental API guess. Exact rationale: the existing execute API cannot acknowledge network admission separately from completion, so merely chaining calls either leaves a cancelAll gap or serializes entire HTTP requests. No other native refactor is authorized by this note.

## 5. Deterministic test contract

Use explicit reached/release barriers (continuations or XCTest expectations with bounded timeout diagnostics), not Task.yield loops, sleeps or scheduler-probability assertions. Signals distinguish: ingress captured; admission begun; admission receipt registered; executor terminal selected; publication queued; cancelAll completed; old context drained. Barrier waits must suspend outside a decision-critical actor segment; no await between active removal and fixing the result. Test waits time out with the missing event/key named and cleanup releases all waiters.

Two complementary layers:

- Coordinator/adapter tests use a contract-conforming executor double implementing admission receipts and immutable terminal selection. cancel/cancelAll actually settle pending receipts as CANCELLED and cancel tracked fake underlying work/deadlines. Count reply calls and released holders; current ReplyCapture only overwrites its last result and is insufficient to detect double delivery.
- Transport tests use the REAL HTTPExecutor with existing internal HTTPNetworkClient/DeadlineScheduler seams. Extend local TestSupport with explicit acknowledgement barriers. Inject late events into the old network callback/execution identity, not `resolve` after a fake continuation has disappeared. Existing relay/UUID guards remain exercised; do not expose public test-only WebKit/native APIs.

| Test/order | Required observation |
| --- | --- |
| Queued old hello/request/cancel; fence before dequeue | ORIGIN_DENIED/null on that invocation, zero native admission, no fresh session acquisition or fresh id consumption. Include actual proxy ingress, not just direct receive. |
| Receipt registration held; allowed reload enters; release receipt | Revoke waits behind admission; cancelAll sees every admitted request; no escaped native task after drain. New generation stays gated. |
| Success selected; publication barrier held; reload; release publication | Original id/status/headers/body preserved once on old handle, even when document is retired. No fresh handle gets it. |
| NETWORK_ERROR selected; publication held; reload | Original id/code/message preserved once, never ORIGIN_DENIED/null. Repeat representative TIMEOUT and native policy failure to exclude result-shape special cases. |
| cancelAll selected before network terminal | Original id/CANCELLED once; actual underlying task and deadline cancelled. Late response/chunks/deadline ignored. |
| Completion emitted but not yet selected; revoke/network decision orders controlled separately | Winner follows executor decision order, not the emission timestamp or adapter publication order. Exercise BOTH orders. |
| Explicit cancel before response / after response | Original CANCELLED + cancelAck true, or original response + cancelAck false. Ack belongs to separate cancel invocation; no duplicate settlement. |
| Native timeout before completion / completion before timeout | TIMEOUT with stopped work, or original response; late event cannot replace winner. |
| Revoke -> drain held -> trusted fresh commit and hello -> release drain | No fresh native admission while old work exists; fresh session differs and request id 1 succeeds. Deliver old network/deadline callbacks AFTER fresh id 1 starts; fresh task remains unaffected. |
| Rejected foreign/subframe/new-window navigation | Existing active session, high-water mark and pending work unchanged; no cancellation. |
| Allowed navigation/reload, provisional/committed failure, process termination | Each uses same fence/drain path with active requests, not just cancelAll counters. Repeated callbacks/rapid reloads cannot activate a superseded intent. |
| Close twice and destruction without close, with queued and admitted work | No retained adapter, handler or delegate; old tasks/deadlines cancelled, replies settled/retired once and released, no fresh activation. Re-register same handler name on retained WebView to verify removal. |
| Eight concurrent requests, ninth BUSY, reverse completion order, duplicate id | Concurrency/correlation semantics unchanged; control consumer does not serialize HTTP lifetimes or wait for capacity. |

The dirty first-terminal tests are useful seeds, not sufficient ordering proof. Retain their behavioral assertions and add a publication barrier. Replace their busy-yield helpers and restore genuine late-network evidence; do not silently remove an assertion to make the suite green.

## 6. Bounded next phase and exact review gates

No new graph/cards and no implementation in this run. Coordinator accepts/rejects sections 3/4 on this same card, then explicitly releases a fresh implementer and later an independent iosverifier. Suggested bounded stages (tool rounds, not guaranteed runtime):

- Run A, maximum 30 rounds: 1-5 orientation + preserve/diff inherited tests; 6-12 one failing admission/cancelAll race and receipt implementation; 13-22 coordinator ingress/drain tracer tests and implementation, one vertical RED/GREEN slice at a time; 23-27 package regressions/source inspection; 28-30 scoped checkpoint with exact SHA and evidence. This is an intermediate implementation checkpoint, NOT review acceptance or card completion. Park for coordinator release of Run B if full gates are not ready. No more than one native seam extension.
- Run B, maximum 35 rounds: 1-5 exact checkpoint verification; 6-18 deterministic adapter ordering/teardown RED/GREEN slices; 19-28 full Simulator/native/schema gates; 29-35 cleanup, committed scoped evidence, exact-head diff and same-card independent review request. At round 20 report remaining risk; if completion is unlikely by 35, preserve and park rather than consuming an unbounded patch loop.
- Reviewer run: inspect accepted design first, independently execute the gates below against the exact committed candidate and deterministic ordering matrix. Fresh process, not self-review. Return concrete changes or approve exact head. Another same-root failure after this replan goes back to coordinator with event trace, not a new error-code patch.

Commands from repository root, AFTER release; `UDID` must identify a newly owned dedicated Simulator, not a shared device. Keep command output/xcresult under ignored `.artifacts/ios-lifecycle/` and retain sanitized exact counts/results in committed scoped evidence or card metadata before worktree cleanup.

    swift test --package-path native/TransportPackage -Xswiftc -warnings-as-errors
    swift test --package-path ios -Xswiftc -warnings-as-errors
    xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$PWD/.artifacts/ios-lifecycle/focused-derived" -resultBundlePath "$PWD/.artifacts/ios-lifecycle/focused.xcresult" CODE_SIGNING_ALLOWED=NO -only-testing:BridgeLabTests/WKBridgeAdapterTests test
    xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$PWD/.artifacts/ios-lifecycle/full-derived" -resultBundlePath "$PWD/.artifacts/ios-lifecycle/full.xcresult" CODE_SIGNING_ALLOWED=NO test
    xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab -destination 'generic/platform=iOS Simulator' -derivedDataPath "$PWD/.artifacts/ios-lifecycle/generic-derived" CODE_SIGNING_ALLOWED=NO build
    xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab -destination 'generic/platform=iOS Simulator' -derivedDataPath "$PWD/.artifacts/ios-lifecycle/analyze-derived" CODE_SIGNING_ALLOWED=NO analyze
    node protocol/v1/validate.cjs
    OPENSPEC_TELEMETRY=0 OPENSPEC_NO_COMPLETIONS=1 openspec/tooling/node_modules/.bin/openspec validate --all --strict --no-interactive --json
    git diff --check
    shasum -a 256 .artifacts/ios-lifecycle/generic-derived/Build/Products/Debug-iphonesimulator/BridgeLab.app/BridgeLab

Use unique result-bundle paths per rerun. Full suite must include any new coordinator test class registered in Xcode (focused adapter command alone is not enough). Reviewer independently replays both selected-before-publication winners and cancellation-before-network with barriers. No skipped required case; report XCTest counts from output, not expected arithmetic. Package warnings-as-errors is required; avoid the previously reported Xcode local-package suppress-warnings/warnings-as-errors flag conflict. Inspect full diff, preserve parent ancestry, verify universal Simulator app, record exact head/hash and remove only owned Simulator resources with absence checked. No shared backend/fixed-port operations here; actual WKWebView-to-backend and unchanged-installed-binary A/B remain downstream integration/acceptance gates.

## 7. Alternatives and stopping condition

- **Only forward all engine results unchanged:** fixes confirmed terminal reclassification, but does not prove pre-submit admission/revoke ordering, proxy ingress capture or drain ownership. Insufficient as the entire fix.
- **Make MainActor reply publication the terminal decision:** rejected. It can overwrite an executor-selected timeout/response/failure and make cancelAck disagree with the original request. Posting another Task or expanding `replyForRetiredInvocation` does not serialize the network owner.
- **One synchronous shared terminal arbiter or one unified executor/coordinator queue:** viable only if coordinator requires navigation callback entry to be terminal arbitration. All network/deadline/cancel events must use the same decision record BEFORE continuation resumption. More invasive native synchronization/API changes, requiring its own bounded design acceptance; not a fallback a worker may quietly implement.
- **Executor per generation / changed cancelAll to permanent shutdown:** not selected. Conflicts with the reviewed one-executor-per-adapter/stable cancelAll seam and does not remove the need to drain old work before new admission.

Recommended acceptance is the existing executor first-terminal owner plus acknowledged short admission and explicit old-context drain. This note deliberately does not claim the implementation is fixed. If coordinator rejects that interpretation or the additive receipt, return a bounded design decision here before any source edit. Planning completion must not release downstream integration or send this card to product review.
