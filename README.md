# Web–Native Bridge Lab

A small iOS Simulator demonstration of one mechanism:

Web content defines an HTTP request, JavaScript sends it through a native bridge, the installed iOS app performs the request, and the response returns to the web content.

The visible Explain demo is in Russian. Variant A requests a catalog. After the served web assets are replaced and the same installed app reloads, variant B requests a quote. React owns the demo actions and response meaning; native code stays generic.

This lab is intentionally small and is not production-ready.

## The path

    Screen (React)
      requestDefinitions.ts
             |
             v
      BridgeClient -> WebKitNativeBoundary
             |
             v
    App (WKBridgeAdapter -> BridgeEngine -> HTTPExecutor)
             |
             v
    Server (synthetic loopback API)
             |
             v
    opaque status + allowed headers + body
             |
             v
      responseInterpreters.ts -> Screen result/error

The app and the web demo present the same idea as `Экран -> Приложение -> Сервер`. While an action runs, the screen shows the current direction and state. When a reply returns, React either renders the returned catalog/quote or explains the error category.

## Where requests are defined

The web-owned HTTP definitions are in one focused file:

- `web/src/demo/requestDefinitions.ts`
  - `buildCatalogRequest`: GET `/api/catalog?category=books`
  - `buildQuoteRequest`: POST `/api/quote` with a JSON body
  - `buildFixtureRequest`: GET definitions used by the opt-in diagnostics surface

Request construction is separate from response meaning. `web/src/demo/responseInterpreters.ts` parses the opaque native reply, validates the endpoint-specific JSON shape, and classifies HTTP, JSON, business, and invalid-shape failures.

Native production code contains no catalog or quote endpoint registry and no business response models.

## How the bridge works

1. React selects a request from `requestDefinitions.ts`.
2. `BridgeClient` performs the v1 `hello` handshake, allocates a correlated request id, and serializes the request envelope defined by `web/src/bridge/protocol.ts`.
3. `WebKitNativeBoundary` calls `window.webkit.messageHandlers.nativeHTTP.postMessage`. There is no browser `fetch` fallback.
4. `WeakReplyMessageHandler` receives the WebKit message and frame metadata. `WKBridgeAdapter` checks the trusted page/frame and coordinates document lifetime.
5. Unchanged `BridgeEngine` validates the wire message and delegates generic HTTP execution to unchanged `native/TransportPackage/`.
6. The app replies once through the original WebKit callback with status, allowed headers, and an opaque text body, or with a transport error.
7. `BridgeClient` validates correlation and the closed reply envelope. `responseInterpreters.ts` then parses business JSON and the React screen renders the result or error.

The normative wire contract and limits are in `protocol/v1/README.md`.

## Source tree

    web/src/
      bridge/
        BridgeClient.ts             handshake, ids, request/cancel lifecycle
        WebKitNativeBoundary.ts     JavaScript-to-WebKit boundary
        protocol.ts                 v1 web types and reply validation
      demo/
        App.tsx                     Russian Explain screen and action state
        demoTypes.ts                action and screen-state types
        errorPresentation.ts        Russian error presentation
        requestDefinitions.ts       all web-owned HTTP request construction
        responseInterpreters.ts     separate response parsing/validation
        screenText.ts               labels and route-state presentation
        demoState.ts                A/B presentation state
        webIdentity.ts              served-build identity and reload record
        money.ts                    bounded quote formatting
      diagnostics/
        TechnicalPanel.tsx          opt-in engineering surface
      main.tsx                      selects Explain or diagnostics

    ios/Sources/
      BridgeLabApp/
        UI/                         SwiftUI screen and WKWebView container
        WebView/                    WebView model, destinations, load state
        WebKitBridge/               adapter, message handler, reply-once helper
      BridgeLabCore/
        BridgeEngine.swift          wire admission and generic bridge replies
        BridgeLifecycleCoordinator.swift
        BridgePolicies.swift

    native/TransportPackage/        generic Foundation HTTP transport
    backend/                        read-only synthetic web/API service
    protocol/v1/                    normative bridge contract
    scripts/lab                     opt-in local service lifecycle
    scripts/verify                  broader integration evidence runners

The source path above is sufficient to follow the implementation. Deeper design and historical evidence remain linked in `docs/architecture.md` and `docs/integration/FINAL_MATRIX.md`; they are not prerequisites for understanding the demo.

## Five-minute A/B demo

Prerequisites: macOS, Xcode with an iOS Simulator runtime, Node/npm, Swift tools, Python 3, and one Simulator that you own. Commands below keep generated web and Xcode output under ignored `.artifacts/` paths and do not write `web/dist`.

From the repository root:

    npm ci --prefix web
    npm --prefix web run build:a -- --outDir "$PWD/.artifacts/manual-web"
    scripts/lab start --web-root "$PWD/.artifacts/manual-web"
    scripts/lab status --web-root "$PWD/.artifacts/manual-web"

Set the UDID of an owned, booted Simulator:

    UDID=<owned-simulator-udid>
    xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab \
      -destination "platform=iOS Simulator,id=$UDID" \
      -derivedDataPath "$PWD/.artifacts/manual-xcode" \
      CODE_SIGNING_ALLOWED=NO build
    xcrun simctl install "$UDID" \
      "$PWD/.artifacts/manual-xcode/Build/Products/Debug-iphonesimulator/BridgeLab.app"
    xcrun simctl launch "$UDID" lab.webnative.BridgeLab

In the installed app:

1. In variant A, tap `Получить каталог`. Confirm that the returned title/SKU is shown.
2. Replace only the served web assets:

       npm --prefix web run build:b -- --outDir "$PWD/.artifacts/manual-web"

3. Do not rebuild, reinstall, or relaunch the app. Tap `Загрузить обновлённый экран` (or the native `Обновить` button).
4. Confirm the screen identifies variant B, then tap `Рассчитать заказ`. Confirm the returned quantity, currency, and total are shown.

Stop only the owned lab service when finished:

    scripts/lab stop --web-root "$PWD/.artifacts/manual-web"
    scripts/lab status --web-root "$PWD/.artifacts/manual-web"

A stopped status intentionally exits 1 and prints `state: stopped`. Do not run fixed-port lab sessions concurrently, and never kill unrelated listeners.

The opt-in Diagnostics screen is available from the installed app by long-pressing the native version footer and choosing `Диагностика`. It uses the same bridge and has no browser-network fallback.

## Focused verification

These checks cover the refactored source without running the broad Simulator matrices:

    npm --prefix web test -- --run
    npm --prefix web run typecheck
    npm --prefix web run build:a -- --outDir ../.artifacts/demo-implementer-a
    npm --prefix web run build:b -- --outDir ../.artifacts/demo-implementer-b
    swift test --package-path ios -Xswiftc -warnings-as-errors
    xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab \
      -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath "$PWD/.artifacts/demo-implementer-xcode" \
      CODE_SIGNING_ALLOWED=NO build

The web tests use an explicit mocked native boundary. The generic Xcode build proves source/project integration, not the live A/B interaction. Existing full Simulator evidence and runners are linked from `docs/integration/FINAL_MATRIX.md`.

## Explicit limitations

- Simulator and fixed loopback origins only: web `127.0.0.1:8787`, API `127.0.0.1:8788`.
- Synthetic read-only backend; no real credentials, authentication, cloud deployment, device signing, or publication.
- Trusted web code receives a bounded HTTP capability for the allowed API origin. This is not a production trust-bootstrap design.
- No browser `fetch` fallback, retry/cache platform, binary/file API, or new recovery behavior.
- Cancellation stops local network work but cannot roll back a server-side effect.
- The demo preserves the behavior of revision `d1aef8a`: its A-to-B explanation can use the current WKWebView's session storage, but continuity across a recreated WKWebView is not solved. Rare redirect/lifecycle work beyond that baseline is deliberately out of scope.

For the approved mission and deeper constraints, see `docs/agent/OWNER_MISSION.md`, `docs/architecture.md`, and `protocol/v1/README.md`.
