# Explain v2 integration design

## Confirmed seams at baseline

- `web/src/App.tsx:45-125,168-285`: both scenarios available in both variants; an accumulating status panel follows Diagnostics. Existing UI tests include hostile-body inert rendering and concurrent slow cancellation.
- `web/src/bridgeClient.ts:98-109,206-273`: closed helloAck, request Promise and terminal reply only. `request()` may still await hello. No native-dispatch/server-progress event is observable. Do not add fields to helloAck or invent progress.
- `web/src/scenarios.ts:24-45,92-126`: web constructs catalog GET / quote POST and interprets opaque bodies, but returns summary strings rather than structured presentation data.
- `web/vite.config.ts:4-11`, `web/src/main.tsx`: compiled `__LAB_VARIANT__`, content-hashed Vite entry. Current A/B differ only in default selection.
- `ios/Sources/BridgeLabApp/BridgeScreen.swift:39-77`: fixed web URL, nonpersistent WK store, generic model, existing cache-bypassing native reload and load-error callback. `WKBridgeAdapter.swift:72-95,130-187` owns navigation revocation/commit/failure; preserve its ordering.
- `ios/BridgeLab/Info.plist:17-20`: runtime Bundle has short version and build. No web-supplied native version is needed.
- `backend/README.md:15-29,52`: web root replacement read from disk, no-cache static responses and existing CSP. Reload is WK document navigation, never API fetch.
- `SameBinaryTests.swift:43-118` and `scripts/verify` share A/B setup across stage1/2/3/5. Existing hashes/container/UDID comparisons are stronger than a UI badge.

## Decisions (shared by every later slice)

### D1. Presentation and request state

Keep React, CSS and a small explicit state union, not a general UI framework. Proposed new files `web/src/demoState.ts` (pure state/update comparison), `web/src/webIdentity.ts` (loaded identity and session record), and `web/src/TechnicalPanel.tsx` (relocated current controls). These are proposed paths, not existing APIs. `App.tsx` owns the main Explain view; `main.tsx` selects TechnicalPanel only when the URL has exactly one `mode` value equal to `diagnostics`; absent, unknown or repeated mode values select the demo. This is presentation selection, never a trust/capability grant. Both surfaces use the same production BridgeClient. There is no diagnostics control in the web demo; the installed-shell entry is the native footer context menu specified in D5, not a browser URL or a new web-to-native command. Keep the separate `web/acceptance/` raw reliability harness.

W owns this bootstrap contract in both compiled A/B builds and tests it before N adds native entry. Diagnostics does not run demo actions or read/consume demo history; on its actual bootstrap it removes only `per85.explain.v1` (storage exceptions remain nonfatal). Returning to the demo boots the currently served build with no manufactured A→B transition. The engineering URL in README is explanatory; opening it in a browser has no native bridge. README must document the installed context-menu gesture and accessible actions in D5, marking them pending N until that slice is reviewed.

Main states: connecting → A intro → catalog pending → catalog result → update requested → reloaded A unchanged / reloaded changed A / B quote ready → quote pending → quote result. Each request can reach an adjacent typed error with retry of the same action. B cold-start goes directly to quote ready, with no invented prior A history. Busy states disable the primary action synchronously and reject duplicate activation; stale completions cannot repaint after unmount/reload. Attach/detach the existing pagehide lifecycle correctly. Preserve cancellation on pagehide/native navigation; main UI need not expose the engineering Cancel control.

### D2. Observable event-to-copy map

| Observed event | Allowed UI / direction | Forbidden inference |
|---|---|---|
| Connecting to native / connect rejected | “Подключаемся к приложению” / clear bridge error, business action disabled | server contacted |
| User selects catalog/quote, operation pending | “Ждём ответ через приложение”; forward Screen → Application → Server route labelled as explanatory | native admitted, server received, server is calculating |
| Valid correlated response Promise resolves | reverse Server → Application → Screen, “Ответ получен” | HTTP response equals business success |
| Web interpreter returns valid business result | adjacent actual item/quantity/amount, “Экран показывает результат” | placeholder data becoming a receipt |
| HTTP/business/parse failure after response | reverse route remains for correlated non-2xx, business-error and malformed/invalid response bodies; category-specific Russian error, no successful receipt | “Сервер не ответил” for an actual HTTP response |
| Transport/protocol/bridge rejection | stop pending, neutral route and truthful category-specific error | pinpoint the failure at server without evidence |
| Page reload requested | “Загружаем веб-экран”; route retained as explanation, not active business transfer | nativeHTTP request / publication success |

No artificial minimum request duration. Fast responses may skip intermediate paints; tests must not require five timed steps. A pulse/directional illustration may run while pending, labelled “Схема обмена; точный этап сервера не виден”, without claiming measured timing or acknowledgement. Reduced motion disables animation but leaves textual direction and status intact.

### D3. Actual data, Russian display, errors

Retain existing request builders: category `books`, SKU `notebook`, quantity 2. Extend ScenarioResult to a discriminated result carrying validated catalog items/total or quote fields in addition to the existing diagnostic summary; never parse a summary string to recover numbers. Keep technical summaries compatible or update every direct consumer/assertion in the same slice. Russian UI labels can describe `notebook` as “Блокнот”, but the response's title/SKU and actual returned values must remain traceable; unknown items must not become a notebook. Format validated returned minor units/currency, not hardcoded `12,00 $`. Unsupported/malformed money fields produce a web interpretation error, not a receipt. Test changed backend values so a constant receipt cannot pass.

Map HTTP, business, invalid JSON/shape, TIMEOUT, CANCELLED, NETWORK_ERROR, other transport policy failures and unavailable/malformed bridge to distinct understandable Russian messages. Preserve underlying categories/status/body in the engineering surface as inert React text, never innerHTML. Retrying a failed connect requires a fresh client/session attempt (current rejected sessionPromise is cached); prefer a bootstrap-owned client recreation over weakening wire validation. Browser mode shows unavailable, never fetch fallback. Do not mask the error with an old success from the same action.

### D4. Real web replacement and honest history

Publication is presenter-owned: build A/B into ignored output and replace the served root only when a build completes. Use existing `scripts/lab --web-root` and verification runner web-build flow. No publish button or new backend endpoint. Participant CTA performs a real same-origin top-level `window.location.reload()`; existing static no-cache headers and adapter navigation policy apply. Keep native cache-bypassing reload as a small secondary recovery affordance, never a competing prominent CTA. Both reload paths revoke the old document.

Identity is `{variant, entryPath}`: compiled `__LAB_VARIANT__` plus the content-hashed emitted entry URL observed via `import.meta.url` in the bootstrap. Display a compact A/B plus entry-basename label; use full identity for comparison. This is loaded build identity, NOT a cryptographic app-integrity attestation. Development/unrecognizable URLs display “версия веб-сборки недоступна”, never a made-up ID. Tests verify bundled identity, not only props in jsdom; no timestamp/counter or caller-selected variant overrides.

A bounded same-origin sessionStorage record `per85.explain.v1` contains a closed versioned record: `{v:1, previous:{variant,entryPath}, catalogSeen:boolean, updateRequested:boolean}` only. Validate types, lengths (entryPath <=256), allowed local entry-path shape and variants; no bodies, tokens, native identity or trusted capability state. Save before participant reload; consume only after React has booted and bridge startup has been attempted. Storage failure/corruption is nonfatal: show loaded capability/identity, but no comparison/history claim. Values are untrusted UX continuity, never security proof. Updating the native recovery path need not synthesize this record.

- Same loaded identity after an update request: “Загружен прежний веб-экран. Попросите ведущего обновить его”; keep A behavior. Do NOT assert “ещё не опубликован”: the app cannot know presenter state.
- Changed identity, still A: “Веб-экран обновлён; расчёт пока недоступен”; do not unlock B.
- Actual B boots: quote action exists; if valid A history exists, explain the transition; otherwise state only current B capability.
- Repeat after B result clears request state to B quote-ready. Full A→B repeat requires presenter re-serving A and a real reload; never reset a local version variable to A.

### D5. Generic native shell and failed document recovery

Make the native chrome light and compact. Show actual `Bundle.main` short version/build in a stable footer with accessibility ID `lab.nativeVersion`; absence is labelled unavailable. This footer remains visible alongside web before/after copy. Wording explains that web changes use already supported native HTTP and do not require replacing the app; a static badge or storage history never asserts a measured same-binary proof. That proof remains external installed-file equality evidence.

Use only generic load presentation in BridgeWebViewModel/adapter: started, document finished, failure. Optional typed load callback replacing the current string callback is local Swift plumbing, not new web wire telemetry. Preserve current revocation order and exact navigation/trust policy. Do not treat `didFinish` as React readiness or a new version. On provisional/navigation/process failure, show a Russian adjacent retry state and suppress interaction with the revoked old document. Retry uses the selected fixed destination below with the existing cache-bypassing request. A new allowed committed document is required before business requests resume.

#### Installed engineering entry (R1 decision, owned by N)

- Attach a native SwiftUI context menu to the stable version footer `lab.nativeVersion`, outside the web content and main CTA. Long-press that footer to reveal `Диагностика` (`lab.openDiagnostics`) and `Вернуться к демо` (`lab.openDemo`). Keep both choices in the menu in either mode; selecting one requests its fixed destination even if already selected. Add the same named VoiceOver custom actions to the footer and an accessibility hint describing the long-press/actions. README is the manual discovery path; no always-visible Diagnostics button or arbitrary address field.
- Add a closed shell-local `WebSurface` enum (`demo`, `diagnostics`) inside `BridgeScreen.swift`. Map it only to `http://127.0.0.1:8787/` and `http://127.0.0.1:8787/?mode=diagnostics`. Default to demo on a fresh model; keep selection only in memory, independent of loaded A/B variant. Set the selected surface before requesting navigation, not on `didFinish`, so a failed diagnostics load still retries diagnostics. Do not accept a URL/string from web, storage, launch arguments or a deep link. This is two fixed web destinations, not native business/screen routing or a change to TrustedPagePolicy.
- Both menu/custom actions and native `lab.reload` use `loadCurrentContent()` with the selected destination, existing `.reloadIgnoringLocalCacheData` and timeout. Participant `window.location.reload()` preserves its current URL. Returning to demo is a fresh navigation to `/` (not WebKit back history), never a local reset to A. Version footer, menu and native reload stay available during loading, missing-assets fallback and errors; retry preserves selection, and the return action can recover to demo even if diagnostics never booted. All navigation still goes through adapter revocation/commit; no production JS injection, new handler, browser-fetch fallback, app relaunch or install is involved.
- N's shared UI test must open the menu with `press(forDuration: 1)` on `lab.nativeVersion`, wait for the menu action identifier, tap `lab.openDiagnostics` and require the real production Diagnostics content. After `lab.reload`, require Diagnostics again, then execute the existing body/category/timeout/concurrent slow-only-cancel assertions and return with `lab.openDemo`; require the current B demo and absence of Diagnostics controls. This action sequence is used only for Stage5, AFTER the unchanged installed-app A/B proof. Stage2/3 still reload `/` after the host replaces the root with the separate acceptance build; they do not select diagnostics mode.
- No runner change is needed for this ingress: `scripts/verify:309-312` already leaves production B at the root and emits Stage5 control files before `finish`; `backend/server.mjs:388-405` strips the query for static lookup and serves the same root index. `TrustedPagePolicy` already permits main-frame navigation to this exact origin; no policy change is required. N changes `SameBinaryTests.swift` to enter/return before signalling `matrix-observed`, so the existing host log and installed-file checks include those actions. N owns this complete Stage5 prerequisite; R's future `simulator-explain-v2` mode is not required. Test failure/retry route preservation in N's focused shell/WebKit tests and prove accessible entry in the installed UI; never substitute a raw harness or URL opened outside the app.

Add a static Russian bootstrap fallback in `web/index.html` root: if JS never loads, the user can see that the screen has not started and use native reload. React replaces it on actual boot. Missing assets, static HTTP 503 and load errors must never show “new version loaded” based on native didFinish. A timed UI reminder, if needed, can only say loading has not completed, never mark success. No native decoding of web scenarios, version counter or business response models.

### D6. Layout and evidence

Use the reference's light surface/turquoise accents, compact three-role route and current result before primary action. Do not reproduce the outer fake phone frame/prototype controls. One prominent primary action per actionable state; completion can have only a secondary repeat action. Route, current status/result, action and native identity should fit together from scroll top at default text size in 320×740, 390×844 and 1100×900 full content viewports, accounting for native safe areas/chrome on Simulator. Never clip/hide current errors to make measurements pass. At enlarged text allow vertical scrolling, keep the route available, and avoid overlap/horizontal overflow. Use semantic headings, labels, status live region, alerts, non-color state cues and >=44pt/CSS-px touch targets.

Browser/jsdom tests with explicit native doubles prove state/layout only. Actual WKWebView tests prove network, update and load recovery. Every layout observation resets scroll to top before measuring or screenshotting; automatic scrolling caused by tap is not proof of initial placement. Retain screenshots/accessibility trees with the exact source head. No need to enable production inspectability.

## Rollback and stop conditions

Any required change to nativeHTTP schema, origin policy, transport limits or lifecycle ordering stops the slice for technical replanning. Do not quietly broaden scope. Preserve rejected review/evidence; at most two same-root rework cycles. Rollback is a reviewed revert of scoped UI/shell changes and re-serving known-good A/B assets, not clearing system caches or modifying accepted historical reports. No archive before source/tests/spec conformance and independent gates.
