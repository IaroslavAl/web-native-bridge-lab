# Lifecycle stage A — intermediate checkpoint, not RC

Coordinator release: own-card RUN A ONLY instruction and `per85-ios-lifecycle-run-a.md`; accepted executor-linearized design: `LIFECYCLE_REPLAN.md` at `dd550c82fb202011ecb699fb493917b7f0873c0b`. Original implementation acceptance remains unmet. Park this same card for coordinator stage acceptance; do not release integration or request product review from this checkpoint.

## Exact inputs and output

- Task/board: `t_b5aeb77f` / `web-native-bridge-lab`; declared project `p_ce173eae` (project association is not independently exposed in this worker's show response).
- Workspace: `/Users/agent/hermes-clean-20260903/projects/web-native-bridge-lab/.worktrees/t_b5aeb77f`.
- Branch: `web-native-bridge-lab/t_b5aeb77f-per-85-ios-bridge-implementer`.
- Stage A implementation head: `0bf760a5b9e87df7bb68f9bb7e31f6ade3df434c`. This note is a subsequent documentation-only commit; the own-card checkpoint comment records its exact final HEAD.
- Verified Git common-dir: `/Users/agent/hermes-clean-20260903/projects/web-native-bridge-lab/.git`. Approved transport `b5c5423c585b8599f5639075e5c40c8a5f517ada` and foundation `e9f338142735b754362c59ed62ad1fa8450c0b4e` already ancestors; no merge necessary.
- Live worker PID 1654 argv: profile iosimplementer, provider openai-codex, model gpt-6-astra, reasoning high. Run A only, maximum 30 tool rounds; round-20 checkpoint posted on own card.

## Scoped changes

1. `native/TransportPackage/Sources/TransportPackage/TransportPackage.swift`: additive `submit` / `HTTPSubmission` / `HTTPExecution`. Submit returns from one non-suspending executor actor segment after validation, task registration, deadline registration and resume. Immediate failures do not create tasks. `execute` remains a submit-and-await compatibility wrapper.
2. `native/TransportPackage/Tests/TransportPackageTests/AdmissionTests.swift`: real executor receipt/cancelAll/reused-id, capacity/duplicate/reverse-completion and immutable-failure/receipt-release regressions. Network events use existing injected lower-layer seams, not a fake executor's cancellation counter.
3. `ios/Sources/BridgeLabCore/BridgeLifecycleCoordinator.swift`: MainActor short control inbox, synchronous generation fence, acknowledgement before ordered revocation, separate originating-result publication workers, drain before fresh activation. `BridgeAdmission` carries an immediate bridge reply or a real HTTP receipt. Located in Core rather than App because it contains no WebKit dependency and is executable by focused package tests. It is NOT wired into the shipping adapter yet.
4. `ios/Tests/BridgeLabCoreTests/BridgeLifecycleCoordinatorTests.swift`: one controlled vertical trace through the production coordinator and real HTTPExecutor with injected network task.
5. `docs/architecture.md`: narrowly documents the coordinator-approved additive native seam and executor first-terminal ownership. Normative protocol/specs unchanged.

## Fresh execution evidence

Commands ran from the exact workspace above; all output is under ignored `.artifacts/ios-lifecycle/`. This table retains the essential evidence if disposable logs are removed.

| Command | Actual result | Disposable log |
| --- | --- | --- |
| `swift test --package-path native/TransportPackage -Xswiftc -warnings-as-errors --filter AdmissionTests` before implementation | RED exit 1: HTTPExecutor has no member submit; dependent type-inference errors. Missing API compile RED, not an observed baseline runtime race. | `stage-a-native-red.log` |
| Same focused native command after first receipt implementation | GREEN exit 0: 1 XCTest, 0 failures | `stage-a-native-green.log` |
| `swift test --package-path native/TransportPackage -Xswiftc -warnings-as-errors` after compatibility regressions | PASS exit 0: 38 XCTest, 0 failures; includes existing execute/cancel/deadline/security/body-cap regressions | `stage-a-native-regression.log` |
| `swift test --package-path ios -Xswiftc -warnings-as-errors --filter BridgeLifecycleCoordinatorTests` before coordinator implementation | RED exit 1: missing BridgeLifecycleCoordinator and BridgeAdmission plus dependent inference errors | `stage-a-coordinator-red.log` |
| Same focused coordinator command after implementation | GREEN exit 0: 1 XCTest, 0 failures | `stage-a-coordinator-green.log` |
| `swift test --package-path ios -Xswiftc -warnings-as-errors` | PASS exit 0: 11 XCTest, 0 failures | `stage-a-ios-regression.log` |
| Same iOS package command after strengthening the pre-executor-hop barrier | PASS exit 0: 11 XCTest, 0 failures; 8 engine, 1 coordinator, 2 policy | `stage-a-ios-final.log` |
| `git diff --cached --check`; staged diff/security/debug scan | PASS; zero scanned secret-assignment/eval/exec/shell/pickle/print/TODO/FIXME patterns | Terminal/card handoff |

The separate Swift Testing runner reports zero tests; it is not substituted for XCTest totals. macOS package tests do NOT execute the conditionally compiled WKBridgeAdapterTests. No Simulator suite, generic app build, analyze, schema/OpenSpec, socket server or backend run in this authorized stage. No new app path/hash is claimed.

## Controlled trace and ownership inspection

The coordinator trace has named XCTest expectations with 3-second diagnostic bounds and continuation gates released in defer, without sleeps/yield loops:

1. Trusted commit intent precedes the invocation in the inbox.
2. Admission begins but its executor hop is held. Revoke enters with zero native tasks, fences old ingress and queues cancelAll. Fresh commit intent queues behind drain.
3. Release the hop; real executor registers one task. Hold the acknowledgement before returning the receipt. Assert cancellation has not overtaken admission and fresh activation has not run.
4. Release receipt; queued old invocation is denied without calling its admission closure. Ordered cancelAll cancels the real executor's registered task. Its originating reply is id 1 / CANCELLED, not ORIGIN_DENIED/null.
5. Hold that old publication. Fresh activation remains gated. Release publication; fresh activation runs and retained publication-record count is zero.

Native receipts preserve values selected before any result waiter; repeat reads cannot replace a terminal. Late old network events after cancelAll cannot affect fresh id 1. Eight submit calls return running receipts without HTTP completion; ninth is immediate BUSY and duplicate id is INVALID_REQUEST, with exactly eight created tasks. Reverse-order responses retain ids. A selected NETWORK_ERROR survives cancelAll. A weak receipt reference becomes nil after caller release: there is no executor completed-result history.

The existing execution UUID, relay, request/response bounds, deadline and credential/origin policies are unchanged. Terminal active-record removal and receipt resolution happen in the same executor actor segment with no await; receipt state is lock-protected and continuations resume outside the lock. The old defensive active-nil check during task/deadline registration is unnecessary in this non-suspending actor segment.

The control inbox contains only short admission/lifecycle commands; it never waits for capacity or retries BUSY. Result workers, not the consumer, await HTTP lifetimes. Consuming is set before launching the single consumer and cleared on exhaustion, so there is no permanent idle consumer task. Completed publication records are removed and result workers weakly reference the coordinator. Native capacity remains eight live tasks, not a total-memory or arbitrary message-flood bound. The inbox has no new fixed message-count limit; production admission callbacks must remain short, and publication callbacks must not await the inbox. The test-only publication suspension is a controlled barrier, not a proposed production delay.

## Preserved inherited work

`ios/Tests/BridgeLabCoreTests/WKBridgeAdapterTests.swift` remains dirty and UNSTAGED, byte-for-byte identical to entry:

`7e6b53bbe6db2a3b698936d2b5cf34b62e934842e115cb59e110682dfcc0d73b`

It contains run63's two first-terminal winner tests and a changed cancellation fake configuration. These are neither approved nor included in the Stage A commit. Their resolve-then-reload recipe lacks a publication barrier, and the fake late-success resolve after cancelAll may find no pending continuation; retain behavioral assertions but do not cite it as real late-network evidence. This explicit inherited dirty path means the worktree is not globally clean.

## Required fresh Run B, only after coordinator release

- Split BridgeEngine validation/admission from waiting for results; evolve its HTTPExecuting seam without a default Task-wrapped execute implementation falsely claiming acknowledged admission. Preserve all validation/session/high-water behavior and existing tests. This stage deliberately leaves BridgeEngine unchanged and execute-based.
- Connect the coordinator to the actual WKBridgeAdapter/proxy ingress before any Task hop. Delete post-generation terminal guessing, keep originating handle identity and generation trust. Current adapter still has the unapproved R3 flaw: Stage A does not fix the shipping call path.
- Complete permanent close/destruction ownership, handler/reply release, idempotent revocation and rapid/overlapping activation intent tests. Current minimal coordinator offers commit/revoke/receive, not a complete closed-state or deinit solution. Ensure callbacks/closures do not retain the adapter/WebView.
- Register coordinator source/tests in the checked-in Xcode project as appropriate. Test import/module arrangement must work in its app-hosted target, not only SwiftPM.
- Execute the accepted selected-before-publication response/error matrix, native cancellation-before-late-network/deadline, explicit cancel/timeout ordering, fresh-session/id-1, eight concurrent coordinator requests, proxy/queued old messages, navigation/failure/termination/close/destruction/release matrix. No claims for these omitted tests here.
- Run the full scoped gates from LIFECYCLE_REPLAN section 6 on a newly owned dedicated Simulator, cleanup/absence checks, generic universal build/hash, analyze, native and iOS packages, protocol/OpenSpec. Preserve exact-head evidence and request fresh independent same-card iOS AND native review only after Run B is ready. Any new same-root failure returns to coordinator, not an automatic patch loop.
- Real WKWebView-to-backend and unchanged installed binary A/B remain downstream integration/acceptance. Do not merge this intermediate head into those lanes as an approved candidate.

No services, Simulator state, shared ports, profiles, runtime, other worktrees, graph, GitHub or owner-facing deployment changed. No child agents/cards, publication or main merge. Coordinator stage acceptance is the required parking gate, not a new owner question.
