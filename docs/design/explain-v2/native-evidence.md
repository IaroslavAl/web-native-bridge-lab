# Explain v2 native implementation evidence

Candidate phase: N only. This record does not claim runtime/layout phase R, independent final acceptance A, owner RC readiness, production deployment, real-device behavior, or non-loopback networking.

## Implemented scope

- `BridgeScreen` remains a light SwiftUI shell around the existing production `WKWebView`. It presents an app title, a Bundle-derived version/build footer, and one compact native context menu rather than duplicating the web journey.
- The shell owns exactly two closed destinations: demo at `http://127.0.0.1:8787/` and Diagnostics at `http://127.0.0.1:8787/?mode=diagnostics`. No arbitrary native URL input was added.
- Long-pressing `lab.nativeVersion` exposes `Диагностика`; equivalent named accessibility actions expose Diagnostics, reload, and return-to-demo behavior. `lab.openDiagnostics`, `lab.reload`, and `lab.openDemo` remain stable automation identifiers.
- Native identity is read from `CFBundleShortVersionString` and `CFBundleVersion`. Missing values are labelled unavailable; no hard-coded version claim is substituted.
- Generic `WKNavigationDelegate` callbacks report loading, completion, and typed content-unavailable failure without changing bridge wire, trust, request, cancellation, or revocation ordering. A stale `didFinish` after revocation is ignored.
- While loading or failed, web interaction is suppressed. Failure presents a native `Повторить` action; retry reloads the selected fixed destination, and Diagnostics also offers `Вернуться к демо`.
- Stage5 `SameBinaryTests` now enters production Diagnostics through the actual installed footer menu after B, uses native reload while retaining Diagnostics, preserves all existing error/body/timeout/concurrency/cancel assertions, returns to demo B, and then completes the matrix observation. Stage2/3 continue using their existing raw-root flow.

## Test-first evidence

Focused native regressions were written before the production shell changes. The first focused `WKBridgeAdapterTests` run exited 65 because the new closed-surface, shell-state, identity, and load-event behavior did not exist. After the minimal implementation, the focused suite passed. A later regression exercising `didFinish` after provisional failure also exited 65, then passed after `WKBridgeAdapter` refused to publish completion for an inactive document.

The final assertions cover fixed destinations, Bundle identity including unavailable values, selected-destination retry/return, interaction enablement only after completion, typed load events, and stale completion suppression. They are integrated into the existing provisional-failure regression so the unchanged Stage4/Stage5 runners retain their reviewed exact test-count contracts.

## Executed gates

Commands ran from branch `web-native-bridge-lab/t_d52592d4-per-85-explain-v2-native-implementer`, based on parent head `18ee515d9f50d236ed05beba8bb790c0adf4055c`. The final commit identity is recorded in the same-card review handoff.

- `swift test --package-path ios -Xswiftc -warnings-as-errors` — PASS: 19 tests, 0 failures.
- `xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab -destination 'generic/platform=iOS Simulator' -derivedDataPath "$PWD/.artifacts/explain-native-build" CODE_SIGNING_ALLOWED=NO build analyze` — PASS: build and static analysis succeeded.
- `scripts/verify simulator-stage4-webkit-privacy` — PASS at `verify-simulator-stage4-webkit-privacy-69644715c0`: 53 tests, 0 failures; owned fixture stopped and owned Simulator removed.
- `scripts/verify simulator-stage5-production-ux` — PASS at `verify-simulator-stage5-production-ux-2b1ef06ddf`: 42 native tests plus 1 installed-shell UI test, 0 failures; installed container and manifest unchanged through A/B/Diagnostics; owned services stopped and owned Simulator removed.
- Post-run listener checks found no process listening on task ports 8787 or 8788.
- `git diff --check` — PASS before evidence finalization.

A first Stage4 verification attempt executed 58/58 tests successfully but the runner correctly rejected the changed total against its reviewed 53-test contract. The N implementation did not alter `scripts/verify`; the new focused assertions were folded into an existing regression and the canonical Stage4 and Stage5 gates were rerun successfully.

## Deliberate limitations and pending gates

- All runtime evidence is Simulator-only against synthetic loopback services. It is not proof of real-device networking, production hosting, authentication, publication, or App Store readiness.
- Stage5 proves the installed footer ingress, native Diagnostics reload, retained production diagnostic outcomes, return to B, unchanged installed app, and owned cleanup. It does not replace R's missing-asset recovery, viewport/safe-area, Dynamic Type, reduced-motion, screenshot, and broader runtime evidence.
- The shell reports only WebKit navigation lifecycle facts. It does not invent server progress, publication state, or business semantics.
- Independent same-card `iosverifier` review remains required. This implementation record and passing gates are not final product acceptance, owner acceptance, OpenSpec archive authorization, or permission to merge primary main.
