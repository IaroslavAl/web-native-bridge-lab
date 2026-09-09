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
- **WHEN** a correlated valid response reaches web
- **THEN** the response direction is explained and only successful web interpretation can display a successful business result; an immediate response requires no minimum animation duration

#### Scenario: Lifecycle revocation
- **WHEN** the user reloads or leaves while a request is active
- **THEN** existing page/native cancellation and document revocation apply and a late old result cannot update the replacement document

### Requirement: EX-03 Actual web-owned data and errors

Web SHALL retain request construction and domain interpretation, show returned catalog/quote values rather than mock receipts, and distinguish bridge/protocol, HTTP, business, JSON/shape, timeout, cancellation and transport failures in understandable Russian. Native SHALL remain domain-agnostic. All untrusted text SHALL be inert.

#### Scenario: Quote data changes
- **WHEN** a B quote response contains a valid quantity, amount or currency different from the reference mockup
- **THEN** the receipt reflects those returned values, not a hardcoded total; invalid money/shape produces an error and no receipt

#### Scenario: Failure and retry
- **WHEN** a catalog or quote request fails, including an HTTP response with an error body or invalid JSON
- **THEN** the error appears beside the retry action with the correct category, no misleading successful result or blanket claim that the server never replied, and retry issues a fresh real operation

#### Scenario: Unavailable or rejected bridge
- **WHEN** nativeHTTP is absent or handshake fails
- **THEN** business actions are unavailable, the user sees a truthful Russian explanation and recovery path, no browser API fetch occurs, and recovery does not reuse a permanently rejected handshake

### Requirement: EX-04 Served capability update

A SHALL expose catalog but not the quote action in the main demo. B SHALL expose the quote capability for notebook quantity 2. The participant update action SHALL load actual served content via document navigation, independently of presenter publication, and SHALL NOT unlock B from storage, a timer or a local flag.

#### Scenario: Same-installed-app A to B
- **WHEN** catalog A succeeds, the presenter replaces only completed served web assets with B, and the participant loads the new screen
- **THEN** the actual loaded identity changes, B quote is available and succeeds through the native bridge, with externally observed identical installed app/container identity and no native rebuild, reinstall or relaunch between A and B

#### Scenario: Unchanged served content
- **WHEN** an update request actually reloads the same identifiable build
- **THEN** the UI reports that the previous screen was loaded, offers retry and does not claim to know whether the presenter has published elsewhere; quote stays unavailable in A

#### Scenario: Different build without new capability
- **WHEN** a changed entry identity still belongs to A
- **THEN** the UI can report changed content but does not claim the quote capability has appeared

#### Scenario: Cold B and repetition
- **WHEN** B opens without valid A history or the user repeats a completed quote
- **THEN** the app reports current B capability honestly, does not invent a prior catalog observation, and repetition cannot simulate reverting the loaded web build to A

### Requirement: EX-05 Real identity and bounded claims

Displayed web identity SHALL come from the actual built/loaded content and native version/build SHALL come from the installed Bundle. Before/after explanation SHALL distinguish changed web capability from existing native capabilities without presenting labels or stored history as binary-integrity proof. Missing identity/history SHALL degrade honestly.

#### Scenario: Runtime version labels
- **WHEN** A is loaded and then B is loaded on the same installed shell
- **THEN** visible web identity reflects each actual entry and the adjacent native label reads the actual Bundle version/build throughout, without a mock version counter or web-supplied native identity

#### Scenario: Corrupt or unavailable history
- **WHEN** session storage is missing, invalid, oversized or inaccessible
- **THEN** current loaded capability remains usable but prior-transition claims are omitted; stored data never authorizes a capability or substitutes an HTTP response

#### Scenario: Meaning of the final comparison
- **WHEN** the demonstrated B quote succeeds after observed A
- **THEN** the UI explains catalog versus quote alongside the native version and that the existing HTTP capability supports both without app replacement, without claiming arbitrary new native functionality or a hash-based proof performed by the UI

### Requirement: EX-06 Failed web loading recovery

Document loading SHALL be distinguished from business HTTP. Initial/update load failure, process termination and missing application assets SHALL leave a truthful recoverable presentation, not an update-success claim or an interactive revoked old document.

#### Scenario: Failed update navigation
- **WHEN** update loading fails provisionally or after navigation, or the web process terminates
- **THEN** the shell presents a Russian error and retry beside each other, suppresses old-document interaction, preserves the native version label and retries the existing trusted root with cache bypass

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

The implementation SHALL preserve existing technical error/cancellation/concurrency/hostile-text assertions outside the main demo, exact origins/limits/wire/lifecycle protections, and reproducible installed-shell evidence. Mock UI and historical results SHALL NOT be relabelled as new runtime acceptance.

#### Scenario: Engineering surface
- **WHEN** the explicit engineering surface is opened
- **THEN** HTTP/body, business, JSON, timeout, fast/slow correlation and slow-only cancellation remain executable through the production client, with hostile bodies inert and no browser fallback

#### Scenario: Runtime handoff
- **WHEN** the candidate is submitted for independent acceptance
- **THEN** evidence names the exact source head, actual A/B assets and backend requests, unchanged installed-file manifest/container/UDID, scroll-top screenshots/accessibility observations, request/update failures and retries, plus stopped owned services, released ports and removed owned Simulator; missing gates are disclosed rather than marked passed
