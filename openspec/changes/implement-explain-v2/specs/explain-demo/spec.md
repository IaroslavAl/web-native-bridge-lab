## ADDED Requirements

### Requirement: EX-01 Focused Russian journey

The production demo SHALL present a bright Russian introduction, a persistent Screen → Application → Server route with request/response direction, and one prominent primary action per actionable state with adjacent current status/error/result. Engineering controls SHALL be outside the main journey.

#### Scenario: Initial catalog screen
- **WHEN** the actual A build starts with an available bridge
- **THEN** the user sees why to request the catalog, the three named roles and one catalog action, without SKU/category/scenario selectors or Diagnostics in the demo

#### Scenario: Useful catalog result
- **WHEN** the catalog request succeeds through native HTTP and web interpretation
- **THEN** the adjacent result shows returned item information and the next action loads served web content, with a concise statement that the presenter changes it separately

### Requirement: EX-02 Observable request explanation

The demo SHALL drive request state from actual client/response/interpreter events, distinguish an HTTP response from business success, and SHALL NOT claim server admission, calculation, timing or native progress that is not observed. Animation SHALL be explanatory only, never a synthetic acknowledgement or artificial success delay.

#### Scenario: Delayed response
- **WHEN** a catalog or quote operation remains pending
- **THEN** the route explains the forward direction and the UI says it is waiting through the application, without advancing through timed server stages, showing a receipt or accepting duplicate primary activation

#### Scenario: Received response
- **WHEN** a correlated response reaches web, including non-2xx, business-error and malformed or invalid response bodies
- **THEN** the reverse response direction is explained without implying business success, and only successful web interpretation can display a successful business result; an immediate response requires no minimum animation duration

#### Scenario: Lifecycle revocation
- **WHEN** the user reloads or leaves while a request is active
- **THEN** existing page/native cancellation and document revocation apply and a late old result cannot update the replacement document

### Requirement: EX-03 Actual web-owned data and errors

Web SHALL retain request construction and domain interpretation, show returned catalog/quote values rather than mock receipts, and distinguish bridge/protocol, HTTP, server business rejection, JSON parse, invalid successful-response shape, timeout, cancellation and transport failures in understandable Russian. Native SHALL remain domain-agnostic. A server business rejection SHALL be recognized only when parsed 2xx JSON is an exact top-level object with the sole own key `error`, whose value is an exact object with the sole own keys `code` and `message`, both nonblank strings. Any parsed object with an own `error` key that is partial, malformed, blank, wrong-typed, or has top-level or nested extra keys SHALL be an invalid successful-response shape before endpoint success validation. Participant copy SHALL dispatch exhaustively over the four web interpretation categories HTTP, JSON parse, server business rejection, and invalid successful-response shape. Server code/message text SHALL remain inert and SHALL NOT select a category or participant copy.

#### Scenario: Quote data changes
- **WHEN** a B quote response contains a valid quantity, amount or currency different from the reference mockup
- **THEN** the receipt reflects those returned values, not a hardcoded total; invalid money/shape produces an error and no receipt

#### Scenario: Failure and retry
- **WHEN** a catalog or quote request fails, including an HTTP response with an error body or invalid JSON
- **THEN** the error appears beside the retry action with the correct category, no misleading successful result or blanket claim that the server never replied, and retry issues a fresh real operation

#### Scenario: Closed business envelope
- **WHEN** a 2xx response contains an exact nonblank `{error:{code,message}}` envelope, misleading server text such as a code beginning with `Unexpected`, a malformed own-`error` envelope, or an invalid endpoint success shape
- **THEN** exact envelopes are server business rejections, malformed envelopes and invalid endpoint results are invalid successful-response shapes, and participant copy follows only the trusted exhaustive category rather than server text

#### Scenario: Unavailable or rejected bridge
- **WHEN** nativeHTTP is absent or handshake fails
- **THEN** business actions are unavailable, the user sees a truthful Russian explanation and recovery path, no browser API fetch occurs, and recovery does not reuse a permanently rejected handshake

### Requirement: EX-04 Served capability update

A SHALL expose catalog but not the quote action in the main demo. B SHALL expose the quote capability for notebook quantity 2. The participant update action SHALL load actual served content via document navigation, independently of presenter publication, and SHALL NOT unlock B from storage, a timer or a local flag. A reload record SHALL preserve `catalogSeen` only from a prior valid-but-untrusted observation record or a successful current catalog result; requesting reload alone SHALL NOT set it.

#### Scenario: Same-installed-app A to B
- **WHEN** catalog A succeeds, the presenter replaces only completed served web assets with B, and the participant loads the new screen
- **THEN** the actual loaded identity changes, B quote is available and succeeds through the native bridge, with externally observed identical installed app/container identity and no native rebuild, reinstall or relaunch between A and B

#### Scenario: Unchanged served content
- **WHEN** an update request actually reloads the same identifiable build
- **THEN** the UI reports that the previous screen was loaded, offers retry and does not claim to know whether the presenter has published elsewhere; quote stays unavailable in A

#### Scenario: Different build without new capability
- **WHEN** a changed entry identity still belongs to A
- **THEN** the UI can report changed content but does not claim the quote capability has appeared

#### Scenario: Rechecking without a catalog observation
- **WHEN** unchanged or changed A is loaded from a valid history record whose `catalogSeen` value is false and the participant requests another reload without a successful current catalog result
- **THEN** the next record preserves false, while a prior true value or a successful current catalog result preserves or records true

#### Scenario: Cold B and repetition
- **WHEN** B opens without valid A history or the user repeats a completed quote
- **THEN** the app reports current B capability honestly, does not invent a prior catalog observation, and repetition cannot simulate reverting the loaded web build to A

### Requirement: EX-05 Real identity and bounded claims

Displayed web identity SHALL come from the actual built/loaded content and native version/build SHALL come from the installed Bundle. Before/after explanation SHALL distinguish changed web capability from existing native capabilities without presenting labels or stored history as binary-integrity proof. Missing identity/history SHALL degrade honestly. Serialized history SHALL be bounded to exactly 512 JavaScript UTF-16 code units and rejected before JSON parsing when larger. After a successful storage get, consumption SHALL attempt removal exactly once before parsing; if removal throws, consumption SHALL return no history without parsing and without claiming durable deletion. A get failure SHALL remain nonfatal but SHALL NOT be described as one-shot consumption.

#### Scenario: Runtime version labels
- **WHEN** A is loaded and then B is loaded on the same installed shell
- **THEN** visible web identity reflects each actual entry and the adjacent native label reads the actual Bundle version/build throughout, without a mock version counter or web-supplied native identity

#### Scenario: Corrupt or unavailable history
- **WHEN** session storage is missing, invalid, oversized or inaccessible
- **THEN** current loaded capability remains usable but prior-transition claims are omitted; stored data never authorizes a capability or substitutes an HTTP response

#### Scenario: Serialized history parse bound and removal ordering
- **WHEN** an accessible serialized history value is at most 512 UTF-16 code units, exceeds 512, storage get fails, or the one removal attempt fails
- **THEN** only an at-most-512 value whose removal returned normally may be parsed, oversized values are removed but never parsed, and get/removal failures return no history without overclaiming deletion

#### Scenario: Meaning of the final comparison
- **WHEN** the demonstrated B quote succeeds after observed A
- **THEN** the UI explains catalog versus quote alongside the native version and that the existing HTTP capability supports both without app replacement, without claiming arbitrary new native functionality or a hash-based proof performed by the UI

### Requirement: EX-06 Failed web loading recovery

Document loading SHALL be distinguished from business HTTP. Initial/update load failure, process termination and missing application assets SHALL leave a truthful recoverable presentation, not an update-success claim or an interactive revoked old document.

#### Scenario: Failed update navigation
- **WHEN** update loading fails provisionally or after navigation, or the web process terminates
- **THEN** the shell presents a Russian error and retry beside each other, suppresses old-document interaction, preserves the native version label and retries the selected fixed trusted destination with cache bypass (demo root by default, diagnostics only after explicit native selection)

#### Scenario: Missing JavaScript or static error page
- **WHEN** the HTML finishes but React does not boot because assets are missing, or the static server returns an error
- **THEN** no code path treats document completion as a successful new React version; an intelligible fallback and native reload remain available, and restoring served content allows recovery without reinstall

### Requirement: EX-07 Accessible compact layout

The route, current outcome and action SHALL be grouped visibly from scroll top at default text size in 320×740, 390×844 and 1100×900 layouts, with native safe areas/chrome accounted for in installed-shell checks. The UI SHALL provide accessible names, status/alert semantics, non-color cues, usable touch targets and reduced motion. Larger text SHALL remain readable without clipping or horizontal overflow.

#### Scenario: Default viewport states
- **WHEN** introduction, pending, result, retry, unchanged-version and final comparison states are inspected at each required size with scroll reset to top
- **THEN** route/current status or result/primary action do not overlap or require scrolling past diagnostics, and current errors are not hidden to make them fit

#### Scenario: Assistive presentation
- **WHEN** reduced motion or enlarged text is enabled and controls are traversed by accessibility focus
- **THEN** animation can stop without losing direction/status meaning, controls have meaningful Russian labels and focus order, and enlarged text can scroll vertically without obscuring content or touch targets

### Requirement: EX-08 Retained reliability and attributable proof

The implementation SHALL preserve existing technical error/cancellation/concurrency/hostile-text assertions outside the main demo, exact origins/limits/wire/lifecycle protections, and reproducible installed-shell evidence. The installed production shell SHALL offer opt-in engineering entry and return through its version-footer context menu and equivalent named accessibility actions, using only fixed same-origin demo/diagnostics destinations. Reload and failed-load retry SHALL preserve the selected destination. Mock UI and historical results SHALL NOT be relabelled as new runtime acceptance.

#### Scenario: Installed production engineering entry and return
- **GIVEN** the real installed app has completed catalog A → actually served B quote without native rebuild, reinstall or relaunch
- **WHEN** the tester long-presses the native version footer and selects Diagnostics, then uses native reload
- **THEN** the production engineering surface loads through the same installed WKWebView/client and stays selected after reload; HTTP status/body, business/JSON categories, timeout, and slow-only cancellation with the fast result retained remain asserted before returning through the same menu to the currently served B demo without diagnostic controls
- **AND** installed-file/container equality and real backend attribution remain checked after those actions, without an arbitrary URL input, browser fallback, production JavaScript injection or replacement by the raw acceptance page

#### Scenario: Accessible entry and failed engineering navigation
- **GIVEN** the native footer exposes named Diagnostics and Return to demo accessibility actions equivalent to its context-menu choices
- **WHEN** diagnostics navigation fails before React boots and the user retries
- **THEN** the footer/actions and native reload remain available, retry targets only the fixed diagnostics URL, the revoked old page is not interactive, and Return to demo loads the fixed demo root even if diagnostics never booted; no business success, web publication or app-replacement claim follows from this navigation

#### Scenario: Engineering surface
- **WHEN** the explicit engineering surface is opened
- **THEN** HTTP/body, business, JSON, timeout, fast/slow correlation and slow-only cancellation remain executable through the production client, with hostile bodies inert and no browser fallback
- **AND** relocated hostile-body tests still assert literal text and absence of injected DOM/side effects; retaining those tests and the separate raw hostile probe is not misreported as a new installed Stage5 hostile-response test

#### Scenario: Runtime handoff
- **WHEN** the candidate is submitted for independent acceptance
- **THEN** evidence names the exact source head, actual A/B assets and backend requests, unchanged installed-file manifest/container/UDID, scroll-top screenshots/accessibility observations, request/update failures and retries, plus stopped owned services, released ports and removed owned Simulator; missing gates are disclosed rather than marked passed
