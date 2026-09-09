# Explain v2 serial delivery plan

Status: proposed execution sequence for coordinator creation AFTER same-card spec review. No child cards or agents created by planning. Names below are logical slices, not existing task IDs; profile bindings must be discovered by the coordinator before card creation. Every body must include the shared D1–D6 decisions from the change design; workers do not decide overlapping interfaces independently.

## Isolation and planning evidence

Planning task `t_9cc1179b`, project `p_ce173eae`, board `web-native-bridge-lab`; workspace `/Users/agent/hermes-clean-20260903/projects/web-native-bridge-lab/.worktrees/t_9cc1179b`; branch `web-native-bridge-lab/t_9cc1179b-per-85-explain-v2-plan-deliverylead`; initial HEAD `778fbb7738212ab817a23aea80685dc1d49cfd78`, clean. Explicit terminal cd/pwd and Git branch/HEAD/common-dir verified; common dir `/Users/agent/hermes-clean-20260903/projects/web-native-bridge-lab/.git`. Absolute-path file-tool writes resolve inside this worktree. Explicit board/task readback confirmed project creation association. `HERMES_KANBAN_TASK` is present; the selected environment lookup did not expose workspace/DB/board values, so no separate environment DB-binding claim.

Configured lead and same-card reviewer: `gpt-6-astra / openai-codex / high`. Actual resumed lead PID 71789 argv independently confirms deliverylead, that model/provider and `--reasoning high`. Reviewer is not launched yet: configured, not observed. No profile modifications. The earlier local OpenSpec install blocker was resolved by coordinator through normal approvals; the resumed worker observes installed CLI 1.12.0. One attempted execute_code copy was denied before execution by headless approval policy; no bypass was attempted. Normal file tools plus read-only Git diff inspection support reference preservation instead.

Only planning docs/specs/reference files may change here. Native, backend, web production, tracked dist and existing test source remain untouched. Historical accepted reports and original graph remain intact. Final planning validation/commit identity belong to the exact same-card lifecycle metadata; no new UI tests or runtime acceptance are claimed by this packet.

## Shared engineering decisions and constraints

Canonical details are `openspec/changes/implement-explain-v2/design.md`. Existing `nativeHTTP` is unchanged; no server progress exists. Use coarse event-grounded phases. Identity is compiled variant plus loaded emitted entry path, history is bounded untrusted sessionStorage, native version stays in SwiftUI from Bundle. Reload is actual top-level navigation, not API fetch or publication. TechnicalPanel is a separate opt-in `?mode=diagnostics` surface. App owns demo state; bootstrap owns runtime identity/client creation; web alone interprets structured business values. These contracts apply to every slice and are not independent worker choices.

Native transport/engine/policies/protocol/backend API/CSP are read-only unless a confirmed out-of-scope defect is escalated. Do not expand this into a generic telemetry or UI framework. All later work uses unique project worktrees, explicit parent reviewed commits merged with preserved identity, serial fixed-port services and same-card independent review via iosverifier. Never self-complete implementation. Coordinator alone updates primary main and later reconciles active OpenSpec lifecycle.

## Small serial sequence

### W — Web journey and content identity

Dependency: approved exact planning/spec head. Intended worker: web-capable implementer (coordinator verifies real profile). Model AND inherited same-card reviewer: `gpt-5.6-sol / openai-codex / high`. Budget 35 planned tool iterations, <=60; goal off, one retry, bounded runtime 3600s. Expected focused work/review: 2–4 hours, not a guaranteed wall clock.

Exclusive ownership:
- Existing `web/src/App.tsx`, `main.tsx`, `styles.css`, `scenarios.ts`, `App.test.tsx`, `scenarios.test.ts` and `web/index.html`.
- Proposed `web/src/demoState.ts`, `demoState.test.ts`, `webIdentity.ts`, `webIdentity.test.ts`, `TechnicalPanel.tsx`, `TechnicalPanel.test.tsx`.
- Existing `web/src/bridgeClient.ts` and tests only if fresh-client bootstrap recovery cannot avoid a narrow handshake fix; stop for review before changing wire semantics. Default: unchanged.
- Existing `web/vite.config.ts`/`vite-env.d.ts` only for build/test wiring, not a new version authority. No dependency addition by default. `web/acceptance/main.tsx` only to keep structured-result consumers compiling; raw probes in `trust.ts` unchanged.
- `README.md` main-demo/engineering invocation and `docs/design/explain-v2/implementation-evidence.md` (new evidence document).

Tasks: write failing semantic/data/history tests first; extract technical controls with all their old assertions; implement D1–D4 plus bootstrap fallback and D6 web layout. Keep summaries compatible with technical consumers. Synchronously guard duplicate activation. Show no-new only after real reload comparison. Fresh B and repeat do not invent A. Tests use explicit native doubles and storage/navigation ports; no production fake boundary or server timer.

Commands (from own worktree; npm ci --prefix web only if needed via normal approvals):

    npm --prefix web test -- --run
    npm --prefix web run typecheck
    npm --prefix web run build:a -- --outDir ../.artifacts/explain-web-a
    npm --prefix web run build:b -- --outDir ../.artifacts/explain-web-b
    node protocol/v1/validate.cjs
    OPENSPEC_TELEMETRY=0 openspec/tooling/node_modules/.bin/openspec validate --all --strict --no-interactive

Evidence must include actual distinct built identities and behavior tests, not label-only snapshots. Do not run every historical Simulator mode while editing web. Cross-layer labels in old SameBinaryTests will be temporarily out of date until N; record this explicitly, never claim integrated PASS. Stop if reliable identity requires a new native API or if money parsing broadens into a finance domain. Request same-card review with exact commit, unchanged protocol assertions and honest pending native/E2E gates.

### N — Generic native presentation and shared UI-harness alignment

Dependency: W reviewed exact commit, merged into own worktree. Intended worker: iOS-capable implementer (coordinator verifies profile). Implementer AND same-card reviewer `gpt-5.6-sol / openai-codex / high`. Budget 30 planned tool iterations, <=60; goal off, one retry, runtime 3600s. Expected 1–3 hours including focused review.

Exclusive ownership:
- `ios/Sources/BridgeLabApp/BridgeScreen.swift`; `WKBridgeAdapter.swift` only generic load-state presentation plumbing without revocation/order/policy changes.
- Focused existing `ios/Tests/BridgeLabCoreTests/WKBridgeAdapterTests.swift`, `LiveWebKitTests.swift`; add shell presentation test coverage to existing Xcode test target if required, with project.pbxproj changes restricted to registering those tests.
- `ios/Tests/BridgeLabUITests/SameBinaryTests.swift`: adapt A/B action semantics and engineering entry navigation for ALL current stage modes while preserving every status/body/cancel/trust assertion.
- `README.md` native recovery wording; `docs/design/explain-v2/native-evidence.md` (new). No concurrent work on SameBinaryTests or README with W/R.

Implement D5: compact light shell, actual native version/build, accessible generic load/retry, revoked-page interaction suppressed, static asset failure never called success. Keep native reload identifier `lab.reload` for recovery and harnesses. Shared test flow now taps web update CTA for the primary A→B proof; engineering entry is explicit and no longer assumed visible on demo. No hardcoded catalog/quote handling in native. Do not rename protocol codes to localize shell text.

Commands:

    swift test --package-path ios -Xswiftc -warnings-as-errors
    xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab -destination 'generic/platform=iOS Simulator' -derivedDataPath "$PWD/.artifacts/explain-native-build" CODE_SIGNING_ALLOWED=NO build analyze
    scripts/verify simulator-stage5-production-ux
    scripts/verify simulator-stage4-webkit-privacy

Stage5 includes actual A/B plus retained engineering outcomes. Stage4 is required once for this mature native slice because load presentation touches lifecycle-adjacent code; host Swift package tests alone do NOT compile/prove the SwiftUI/WebKit adapter. Use dedicated owned Simulators and verify teardown. Do not alter production inspectability, adapter trust or timeout policy for testing. Stop/replan if callbacks disturb lifecycle fences, actual WK reload doesn't preserve intended session semantics, or failed-page UI remains interactive. Request same-card review.

### R — Explain runtime acceptance harness and exact candidate

Dependency: N reviewed exact commit. Intended worker: integration-capable implementer (coordinator verifies profile). Implementer AND same-card code reviewer `gpt-5.6-sol / openai-codex / high`. Budget 35 planned tool iterations, <=60; goal off, one retry, runtime 5400s. Expected 2–4 hours; likely long pole is deterministic WKWebView update/failure coordination and scroll-top layout verification, not CSS authoring.

Exclusive ownership:
- `scripts/verify`, `scripts/tests/test_verify.py`, `ios/Tests/BridgeLabUITests/SameBinaryTests.swift` (serial hotspot; no sibling edits).
- Proposed `ios/Tests/BridgeLabCoreTests/ExplainLayoutTests.swift` and `ios/BridgeLab.xcodeproj/project.pbxproj` solely for registering/running real WK component layout tests. No new browser dependency or production DOM backdoor. These tests load actual built web assets; read-only DOM geometry and test-local interaction are allowed here, never in the installed SameBinary proof.
- `README.md`, `docs/design/explain-v2/runtime-evidence.md` and `runtime-evidence.json` (new), change tasks/evidence links.

Add one bounded `scripts/verify simulator-explain-v2` mode (NEW command; does not exist at planning baseline). Reuse existing installed manifest/container/UDID, actual backend log attribution, stage control files and cleanup rather than build a second runner. Extend host/UI coordination for unchanged A reload, actual B replacement, request failure/retry and update failure/recovery. Host control requests remain test-runner-only on static web port, never supply API results or inject production JS. Exercise missing entry assets/static error and stopped/unavailable service without replacing the bridge. Required semantic tests prove A lacks quote and B gains it, response data changes are respected, repeat stays B, direct B does not invent history, and diagnostic slow-only cancel still preserves fast result.

Layout: record scroll-top frames/screenshots at 320×740, 390×844 and 1100×900, reduced motion, and at least one enlarged-text pass. The new mode runs focused WK component layout tests using explicit WKWebView frame sizes and actual built assets; these are content-viewport observations, not invented Simulator device sizes. Keep this phase separate from installed-app evidence/log attribution. Additionally prove actual WKWebView/safe-area/default and enlarged-text placement in a dedicated owned iPhone Simulator through the installed UI test. No JS native bridge substitution or JS geometry injection in same-binary acceptance. Inspect snapshots as well as numeric geometry; if offscreen/large-frame WK snapshots cannot be captured accurately, report that exact gap for a bounded alternative rather than treating jsdom as visual evidence.

Commands:

    python3 -m unittest discover -s scripts/tests -v
    scripts/verify unit
    scripts/verify simulator-explain-v2
    scripts/verify simulator-stage5-production-ux

The new mode must be implemented/tested before its command is claimed. Run stage2/3 only if runner changes affect their common synchronization/selection or the retained raw/outcome tests; inspect diff and record rationale. Re-run stage4 if native source changes after N. Run `python3 scripts/tests/operations.py` if service ownership/cleanup code changes, otherwise retain the unchanged-baseline evidence with exact diff-based rationale. This is proportional regression, not removal of historical commands/coverage. Every executed mode retains real exit codes and cleanup; no backend/Simulator left running. Product fixes discovered here route back to W/N ownership, not a giant integration rewrite. Request same-card review; runtime harness author is not final acceptor.

### A — Independent exact-RC acceptance (no feature implementation)

Dependency: R independently reviewed exact head and W/N reviewed ancestors. Intended profile `iosverifier` (already specified by this card; coordinator still verifies dispatch profile). `gpt-6-astra / openai-codex / xhigh`, 25 planned iterations, <=60, goal off, runtime 3600s. No broad rerun mandate: independently run `simulator-explain-v2`, strict OpenSpec and targeted conformance checks on the exact candidate; inspect the mature unit/stage4/stage5 evidence and source identity, rerun any changed layer. Verify installed-file equality, real GET/POST logs, raw UI outcomes, layout/assistive checks and cleanup. Missing evidence is not PASS. No source fixes by the final acceptor.

Output: exact source head/branch; requirements EX-01–08 matrix and retained WS/security evidence; configured versus observed model/provider/effort; unresolved limits; honest RU owner candidate summary. Coordinator then performs allowed final integration/lifecycle reconciliation and offers the owner the candidate. Owner retains final product acceptance, not repetitive technical setup approvals. Preserve original completed graph and historical failed evidence.

## Requirement → test allocation (tests are obligations, not executed results)

| Contract | W tests | N/R actual evidence |
|---|---|---|
| EX-01, EX-07 | App semantics, action uniqueness, aria/reduced-motion styles | scroll-top screenshot/frame/focus observations, native safe areas and large text |
| EX-02 | deferred Promise, immediate response, duplicate action, unmount/late response | loading then real response; reload cancellation with existing Stage4 fences |
| EX-03 | varied returned data, invalid fields, every error class, fresh handshake recovery, no fetch | actual catalog/quote, failure/retry, retained Stage5 body/category/cancel assertions |
| EX-04 | A/B gating, identity comparison, same-A/different-A, cold B/repeat | real unchanged A then served B, installed manifest equality, actual backend logs |
| EX-05 | runtime entry extraction, bounded/corrupt/inaccessible session storage | native Bundle values and built entry hash paths read back; never label-only proof |
| EX-06 | static bootstrap fallback and no success before React boot | provisional/process/asset/static error recovery without reinstall |
| EX-08 | TechnicalPanel assertions migrated without omissions | Stage5 retained outcomes, Stage4 trust/lifecycle/privacy, exact regression rationale |

## Executed planning checks

The resumed worker ran project-local OpenSpec 1.12.0 `validate --all --strict --no-interactive --json`: PASS for `add-bridge-lab` and `implement-explain-v2`, two changes, zero failures/issues, zero canonical specs. `node protocol/v1/validate.cjs`: 36 schema vectors PASS (14 valid, 15 invalid, 7 semantic-only classifications); semantic-only error codes were NOT runtime-tested. This is not native/UI execution.

Read-only `git diff --no-index` comparisons confirm exact source-copy equality for both retained reference files. SHA-256: HTML `46f48b0675bf6e0160ecdc7a82ce05430b53df75d0e5e9b1991aa73f1cb381dc`; brief `76510166db453a62ea3e6fcf242c3c8b15e983de7ef370ba931600c995f67a54`. The copied HTML includes an original whitespace-only line; preserve the reference rather than silently rewrite it. New authored Markdown/specs must pass whitespace checks. No Simulator/backend was started by planning, no product code/tests were edited, and no runtime UI PASS is claimed.

## Stop/budget policy and estimate

Stop before 60 iterations or runtime exhaustion, preserve evidence and ask coordinator for bounded technical replanning, not new product approval. At most two same-root rework cycles. Do not work around package/command approvals. All long runs heartbeat and retain process handles; no waiting on unattached agents. No simultaneous fixed-port modes. No installs into other profiles/global tools.

Rough total: one focused working day after reviewed plan; allow a second for review fixes/Simulator coordination. This is a planning judgment, not benchmarked completion time. In Russian: «Основа готова; осталось подключить выбранный интерфейс к реальным событиям и проверить обновление/ошибки на одном установленном приложении. Ориентир — рабочий день, с исправлениями до двух; главный риск — WKWebView и проверка реальных переходов, не создание backend заново».
