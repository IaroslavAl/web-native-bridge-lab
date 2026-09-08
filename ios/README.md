# BridgeLab iOS module

Simulator-only SwiftUI shell and WKWebView adapter for the PER-85 protocol. The app links the local `native/TransportPackage`, trusts only the main frame at `http://127.0.0.1:8787`, and grants the generic HTTP capability only for the native-owned transport origin `http://127.0.0.1:8788`. Web assets are loaded remotely and are not bundled, so the native Reload control (`lab.reload`) can pick up a rebuilt `web/dist` without rebuilding or reinstalling the app.

The WebKit reply handler returns structured JSON-compatible objects directly; response text is never interpolated into JavaScript. A nonpersistent data store, local-network-only ATS exception, navigation denial, per-document session/high-water state, and serialized revocation separate page trust from the transport allowlist.

## Reproduce

From the repository root:

    swift test --package-path ios -Xswiftc -warnings-as-errors
    xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab -destination 'generic/platform=iOS Simulator' -derivedDataPath "$PWD/.artifacts/ios-derived" CODE_SIGNING_ALLOWED=NO build

For Simulator XCTest, replace `<UDID>` with a task-owned or dedicated available iOS Simulator:

    xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath "$PWD/.artifacts/ios-derived" CODE_SIGNING_ALLOWED=NO test

## Coverage and limits

- `BridgeEngineTests`: WB-01 closed/versioned wire parsing, raw cap and validation precedence; WB-03 handshake/session, monotonic IDs, structured safe text, cancel acknowledgement; WB-04 revocation/cancelAll and fresh-document ID reuse.
- `BridgePolicyTests`: WB-02 exact committed URL + WebKit-derived security-origin tuple + main-frame/active checks, and denial of foreign/subframe/new-window navigation.
- `WKBridgeAdapterTests` (Simulator XCTest): WB-04 allowed/rejected navigation, provisional and committed load failure, close, process termination, destruction, queued old hello/request, cancelAll-driven `CANCELLED` retirement, late-success suppression, fresh-document ID reuse, handler ownership, and reply-once behavior.
- `WKBridgeAdapter` maps real `WKScriptMessage.frameInfo.securityOrigin` and `isMainFrame` into that policy, binds every invocation to the captured native lifecycle generation before and after asynchronous handling, preserves the originating id and `CANCELLED` terminal result during revocation without exposing a stale success to a fresh document, registers only in the page content world, serializes revoke/activate work, removes its handler on close/destruction, and uses a weak proxy plus reply-once gate.

This module does not claim real backend/WKWebView A/B acceptance. Final integration still owns the dedicated Simulator, fixture lifecycle, actual WebKit provenance/iframe/reload races, same-installed-binary hashes, and end-to-end cancellation evidence. Simulator and synthetic fixed loopback HTTP only; no credentials, device signing, external origins, business endpoints/models, or production-security claim.
