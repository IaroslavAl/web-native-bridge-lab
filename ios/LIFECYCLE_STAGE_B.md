# Lifecycle stage B — implementation candidate for independent review

Run B explicitly released on task `t_b5aeb77f`, board `web-native-bridge-lab`, declared project `p_ce173eae`. This is not self-approval or final product acceptance. The same-card verifier must review both iOS and the additive native receipt changes since transport approval, against the accepted executor-linearized design in `LIFECYCLE_REPLAN.md`.

## Exact source and environment

- Workspace: `/Users/agent/hermes-clean-20260903/projects/web-native-bridge-lab/.worktrees/t_b5aeb77f`.
- Branch: `web-native-bridge-lab/t_b5aeb77f-per-85-ios-bridge-implementer`.
- Common Git directory: `/Users/agent/hermes-clean-20260903/projects/web-native-bridge-lab/.git`.
- Entry head: `8ef021245622c8a78ddf391e49293bab66b0df8e`, coordinator-accepted Stage A continuation only. Accepted design `dd550c82fb202011ecb699fb493917b7f0873c0b`; approved transport `b5c5423c585b8599f5639075e5c40c8a5f517ada` and foundation `e9f338142735b754362c59ed62ad1fa8450c0b4e` are already ancestors (verified by git merge-base). No merge was required.
- The exact resulting candidate SHA is recorded in the same-card review transition metadata; this committed note is part of that candidate, not a self-referential hash.
- Live worker PID 7558 argv confirmed iosimplementer / openai-codex / gpt-6-astra / high. Board/run/workspace bindings matched environment. No routing/profile changes. Task's project declaration is not independently returned by the task-show top-level schema.
- Apple Swift 6.3.3, arm64 macOS host; dedicated iPhone 17 Pro / iOS 26.5 Simulator. No signing or physical device.

## Implementation and ownership

BridgeEngine now exposes short `admit` returning BridgeAdmission, backed by HTTPExecuting.submit. Its existing handle method remains a submit-and-await convenience for module tests, not the adapter control path. Validation precedence, sessions and high-water marks are unchanged. No Task-wrapped execute is used as a false admission acknowledgement.

The real adapter uses the Stage A MainActor coordinator. Allowed navigation/failure/close synchronously fences ingress. An admission already in progress finishes registration before ordered cancelAll; queued old invocations are denied before admission. Result workers wait independently from the control consumer, so eight HTTP lifetimes remain concurrent and BUSY is not queued waiting for capacity. Fresh committed activation waits for cancelAll and originating old publication records to drain. Rapid superseded activation intents fail generation checks.

Publication no longer rewrites selected results based on the current generation. It converts the immutable executor result and calls only the captured originating WebKit reply. A preselected response or failure remains that response/failure; cancellation wins only at the executor's active-record removal. The internal beforePublication dependency is a default no-op used by controlled tests, not a wire capability. A suspended test publication never waits on the inbox.

The proxy is compiler-checked MainActor and forwards before any Task hop. Actual WebKit callback supplies frameInfo/securityOrigin; the proxy test seam supplies explicit provenance tuples through the same synchronous forwarding path. Close is permanent at the adapter boundary and idempotent. Isolated deinit calls close synchronously on its actor; no task captures the dying adapter. Registration/delegate removal, weak ownership and callback release are exercised with a retained real WKWebView. ReplyOnce clears its closure before calling it. The coordinator owns drain work only until its consumer/publications finish; completed records are removed.

No native production source changed during Run B. Native AdmissionTests adds an actor-isolated test extension to distinguish event emission from selection, without a new production test hook. Stage A's native submit/receipt extension still requires independent regression review.

## Deterministic scenario coverage

| Accepted scenario | Executable evidence |
| --- | --- |
| Short admission before HTTP completion | BridgeLifecycleCoordinatorTests.testEngineAdmissionReturnsBeforeHTTPCompletionAndRevocationSettlesReceipt |
| Pre-executor-hop and held-receipt overlap; old publication drain before fresh activation | BridgeLifecycleCoordinatorTests.testRevocationWaitsForAdmissionReceiptAndPublicationBeforeFreshActivation; adapter testAdmissionOverlapWaitsForReceiptBeforeCancelAllAndFreshHello |
| Selected response and NETWORK_ERROR survive reload before publication | Adapter testCompletedResponseKeepsFirstTerminalResultAcrossImmediateReload and testCompletedTransportFailureKeepsFirstTerminalResultAcrossImmediateReload; each waits for selected value at a publication gate, starts reload, waits for cancelAll, then releases gate |
| Selected native TIMEOUT and policy failure survive reload | Adapter testSelectedTimeoutAndPolicyFailureAreImmutableAcrossHeldPublication uses real deadline and redirect events, with held publication |
| Cancellation-before-network; old callbacks after fresh id 1 | Adapter testOldNetworkAndDeadlineAfterFreshIDOneCannotTouchFreshTask; retained old lower-layer callback and old deadline action invoked after fresh registration; fresh task uncancelled and correct body |
| Emitted but not selected versus selected-before-cancel | Native AdmissionTests.testEmittedCompletionDoesNotWinUntilExecutorSelectsIt: test extension emits into relay while on executor actor, then calls same-actor cancel whose body has no suspension; relay consumer cannot select first. Opposite order awaits real receipt selection before cancel. No sleep/yield/semaphore |
| Explicit cancel / deadline / response ordering | Adapter testExplicitCancelAndDeadlineFollowNativeFirstTerminalOrder; actual executor cancellation acknowledgements, task/deadline ownership, late event offer and callback count |
| Eight concurrent, ninth BUSY, duplicate, reverse replies | Adapter testEightConcurrentAdmissionsBusyDuplicateAndReverseCorrelation plus native AdmissionTests capacity regression |
| Proxy queued old hello/request/cancel and rapid commits | Adapter testProxyQueuedHelloRequestAndCancelCannotCrossRapidActivationIntents; zero old native admissions and fresh id 1 unaffected |
| Rejected foreign/subframe/new-window preserves work/session/id mark | Adapter testRejectedNavigationPreservesPendingWorkAndHighWaterMark and policy tests |
| Allowed navigation, provisional/committed failure, process termination, close twice, destruction without close | Adapter testEveryRevocationEventCancelsAdmittedTaskAndDeadlineExactlyOnce exercises all six named events with queued and admitted work, originating id/CANCELLED, task/deadline cancellation counts, and queued denial |
| Handler, delegate, adapter and reply holder release | Same active-work matrix retains WKWebView and successfully re-registers the handler name after close/destruction; testReplyOnceReleasesCapturedHolderImmediately and testReplyOnceSettlesOnlyFirstResult |
| Wire/security/safe delivery | Existing 8 BridgeEngineTests and 2 BridgePolicyTests remain green; actual frame provenance and end-to-end JS serialization remain integration acceptance |

Adapter transport support now wraps the REAL HTTPExecutor with injected network/deadline seams. It no longer invents terminal outcomes from a fake cancelAll counter. The inherited dirty run63 response/error assertions were retained and strengthened with explicit publication barriers. The late-completion test now emits a real lower-layer event after cancellation; the dedicated old-callback/fresh-id test additionally exercises stale deadline identity. Tests count each originating callback; waits have named three-second XCTest diagnostic bounds and continuation gates are released by defer. Existing earlier native suites retain their historical helper style; Run B's added native test does not use polling.

## Fresh execution evidence

All commands ran from the workspace above. Logs and xcresult bundles are disposable under ignored `.artifacts/ios-lifecycle/`; this committed table and same-card exact-head metadata preserve essential evidence after worktree deletion.

| Command / log stem | Actual result |
| --- | --- |
| `swift test --package-path ios -Xswiftc -warnings-as-errors --filter BridgeLifecycleCoordinatorTests` / stage-b-engine-red | RED exit 1: BridgeEngine.admit missing; API compile RED, not a claimed runtime baseline race |
| iOS package command after engine split / stage-b-engine-green | GREEN 12 XCTest, zero failures |
| Xcode build-for-testing / stage-b-adapter-red | RED exit 65: missing beforePublication dependency for selected-result barrier |
| Focused proxy XCTest build / stage-b-proxy-red | RED exit 65: missing synchronous forward seam |
| `swift test --package-path native/TransportPackage -Xswiftc -warnings-as-errors` / stage-b-native | PASS exit 0: 39 XCTest, zero failures |
| `swift test --package-path ios -Xswiftc -warnings-as-errors` / stage-b-ios | PASS exit 0: 12 XCTest, zero failures |
| Xcode focused WKBridgeAdapterTests / stage-b-focused | PASS exit 0: 23 XCTest, zero failed/skipped |
| Xcode full scheme / stage-b-full | PASS exit 0: 35 XCTest, zero failed/skipped (23 adapter, 8 engine, 2 coordinator, 2 policy) |
| Generic Simulator app / stage-b-generic | BUILD SUCCEEDED, universal arm64/x86_64 Mach-O |
| Generic Simulator analyze / stage-b-analyze | ANALYZE SUCCEEDED |
| `node protocol/v1/validate.cjs` / stage-b-protocol | PASS: 14 valid, 15 invalid, 7 semanticOnly; 36 structural classifications, not a claim of running all semantic codes |
| `OPENSPEC_TELEMETRY=0 OPENSPEC_NO_COMPLETIONS=1 openspec/tooling/node_modules/.bin/openspec validate --all --strict --no-interactive --json` / stage-b-openspec | PASS: add-bridge-lab valid |
| git diff --check, plutil project/Info.plist, xmllint scheme, added-line security/debug scan | PASS; zero scanned secret-assignment/eval/exec/shell/print/TODO/FIXME patterns |

Focused/full command form:

    xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab -destination 'platform=iOS Simulator,id=E7502A44-9110-4A85-B479-640263465C51' -derivedDataPath "$PWD/.artifacts/ios-lifecycle/stage-b-derived" -resultBundlePath "$PWD/.artifacts/ios-lifecycle/stage-b-full.xcresult" CODE_SIGNING_ALLOWED=NO test

Focused uses its own stage-b-focused.xcresult and adds `-only-testing:BridgeLabTests/WKBridgeAdapterTests`. Reproduction must create a NEW owned Simulator and use a new result bundle path; the recorded device was deleted. Generic build/analyze replace destination with `generic/platform=iOS Simulator`, omit resultBundlePath, use stage-b-generic-derived / stage-b-analyze-derived, and select build / analyze.

App path: `.artifacts/ios-lifecycle/stage-b-generic-derived/Build/Products/Debug-iphonesimulator/BridgeLab.app`.
Executable SHA-256: `2ad1f4f6c67709edbdb406e7e6d1397e824e7fcf59fe8474d8da55ace919585c`.
This is the locally built executable, not same-installed-binary A/B evidence or a claim that absolute-path-dependent builds reproduce the same hash elsewhere.

The final Xcode gates emitted only the non-product AppIntents metadata extraction warning (no AppIntents.framework dependency). An earlier weak-variable test warning was corrected before the final run. An initial focused command found an empty shell UDID variable and exited 64 before execution; the literal verified UDID was then used. Package warnings-as-errors gates passed. Earlier intermediate Simulator suites passed 26 and 32 tests before matrix expansion. Regression matrix additions that already passed existing corrected behavior are not claimed as independent runtime RED reproductions of the historical defect.

## Cleanup and downstream handoff

Dedicated Simulator `E7502A44-9110-4A85-B479-640263465C51` was shut down, deleted, and verified absent in fresh simctl JSON. No backend/fixed-port listener, shared Simulator, permanent service, other worktree, runtime/profile or graph was modified. No remote CI, GitHub/Jira, publication or main merge. No child agents/cards.

After independent same-card approval ONLY, integration merges the exact reviewed candidate SHA preserving its ancestry. Shipping origins remain page `http://127.0.0.1:8787` and API `http://127.0.0.1:8788`; install/build commands and accessibility hooks remain in README. Integration separately merges approved web/backend heads and owns serialized service/dedicated-Simulator operations. Child integration `t_9d8fd391` was inspected and remains coordinator-scheduled.

The unchanged-installed-binary A/B proof, real React/WKWebView/backend flow, actual iframe provenance and navigation delivery behavior, populated synthetic credential stores and socket effects on iOS are not claimed here. This module candidate is simulator-only, generic and credential-free, not production-ready. The full mission and OpenSpec are not archived or accepted by this implementation run. A new same-root review rejection must return to coordinator design triage rather than automatic outcome-code patching.
