# BridgeLab iOS module

Simulator-only SwiftUI shell and WKWebView adapter for the PER-85 protocol. The app links the local `native/TransportPackage`, trusts only the main frame at `http://127.0.0.1:8787`, and grants the generic HTTP capability only for the native-owned transport origin `http://127.0.0.1:8788`. Web assets are loaded remotely and are not bundled, so the native Reload control (`lab.reload`) can pick up a rebuilt `web/dist` without rebuilding or reinstalling the app.

The WebKit reply handler returns structured JSON-compatible objects directly; response text is never interpolated into JavaScript. A nonpersistent data store, local-network-only ATS exception, navigation denial, per-document session/high-water state, and serialized revocation separate page trust from the transport allowlist.

## Reproduce

From the repository root:

    swift test --package-path ios -Xswiftc -warnings-as-errors
    xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab -destination 'generic/platform=iOS Simulator' -derivedDataPath "$PWD/.artifacts/ios-derived" CODE_SIGNING_ALLOWED=NO build

For Simulator XCTest, replace `<UDID>` with a task-owned or dedicated available iOS Simulator:

    xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath "$PWD/.artifacts/ios-derived" CODE_SIGNING_ALLOWED=NO -skip-testing:BridgeLabTests/LiveWebKitTests test

The eight opt-in `LiveWebKitTests` require a separate loopback fixture and a fresh
Simulator sandbox for strictly synthetic store seeding. Run them plus the42
regressions through `scripts/verify simulator-stage4-webkit-privacy`; do not point
these privacy tests at an existing personal Simulator. See
[Stage4 layer-specific evidence](../docs/integration/STAGE4_WEBKIT_PRIVACY.md).

The app's compiler-checked `isolated deinit` uses the current Swift toolchain (verified with Apple Swift 6.3.3 and iOS 26.5 Simulator); older Swift compilers are not a supported build claim. Deployment target remains iOS 17 Simulator, without signing.

## Coverage and limits

- `BridgeEngineTests`: WB-01 closed/versioned wire parsing, raw cap and validation precedence; WB-03 handshake/session, monotonic IDs, structured safe text, cancel acknowledgement; WB-04 revocation/cancelAll and fresh-document ID reuse.
- `BridgePolicyTests`: WB-02 exact committed URL + WebKit-derived security-origin tuple + main-frame/active checks, and denial of foreign/subframe/new-window navigation.
- `BridgeLifecycleCoordinatorTests`: acknowledged admission, pre-executor-hop and receipt barriers, cancellation/publication drain before fresh activation, and engine integration with real executor receipts.
- `WKBridgeAdapterTests` (23 Simulator XCTest methods): active-work navigation/failure/termination/close/destruction matrix; queued proxy hello/request/cancel and rapid activation intents; receipt/revoke overlap; selected response/NETWORK_ERROR/TIMEOUT/REDIRECT_DENIED held before publication; explicit cancel/deadline winners; eight concurrent admissions, immediate BUSY and reverse correlation; old native network/deadline events after fresh id 1; handler/delegate/adapter/reply-holder release.
- `WKBridgeAdapter` synchronously maps real `WKScriptMessage.frameInfo.securityOrigin` and `isMainFrame` through a MainActor weak proxy. The coordinator captures generation before any Task hop, orders short engine admission and revocation, and drains old publications before fresh activation. HTTPExecutor alone selects admitted HTTP terminal values; publication preserves that value on its originating Promise and never guesses a replacement from the current generation. Close/destruction removes registration and synchronously fences queued ingress; the short-lived drain retains only coordinator/engine/old receipts and reply holders, not the adapter/WebView.

Exact Run B evidence, deterministic ordering definitions, commands and downstream inputs: [LIFECYCLE_STAGE_B.md](LIFECYCLE_STAGE_B.md). The accepted design is [LIFECYCLE_REPLAN.md](LIFECYCLE_REPLAN.md); historical Stage A and earlier review notes are not the current candidate's acceptance.

This module does not claim real backend/WKWebView A/B acceptance. Final integration still owns the dedicated Simulator, fixture lifecycle, actual WebKit provenance/iframe/reload races, same-installed-binary hashes, and end-to-end cancellation evidence. Simulator and synthetic fixed loopback HTTP only; no credentials, device signing, external origins, business endpoints/models, or production-security claim.
