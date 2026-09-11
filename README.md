# Web–Native Bridge Lab — PER-85

A small Simulator-only foundation: remotely served React constructs requests and parses business JSON; a generic Swift transport executes HTTP through the production WKWebView adapter. This is not production-ready. Only synthetic loopback data is supported; no authentication, cloud service, device signing or publication.

## Prerequisites

macOS with Xcode and an installed iOS Simulator runtime; Node >=20.19 (tested Node 26.5), npm, Python 3.9+, Swift/Xcode command line tools, and `/usr/sbin/lsof`. Dependencies are pinned under `web/` and `openspec/tooling/`; no global install, approvals-policy change or service registration is needed.

## Core verification

From this checkout:

    scripts/verify unit

Installs pinned local tooling, audits the complete web dependency tree, runs schema/OpenSpec validation, backend HTTP/process tests, native and iOS package tests, React/TypeScript tests and both web builds. Output goes to a fresh ignored `.artifacts/verify-unit-*/` directory. Commands and exit codes are recorded in `commands.json`; failures return nonzero. Builds use isolated output and do not replace tracked `web/dist`. Unit native/bridge doubles are not proof of actual WebKit networking.

## Final candidate gates and evidence

The [final requirement/scenario matrix](docs/integration/FINAL_MATRIX.md) is the current cross-layer coverage map. Stage1–5 reports below are historical checkpoints, not five outstanding product phases. Run separately and serially after the unit command:

    python3 scripts/tests/operations.py
    scripts/verify simulator-explain-v2
    scripts/verify simulator-stage2-outcomes
    scripts/verify simulator-stage3-trust-limits
    scripts/verify simulator-stage4-webkit-privacy
    scripts/verify simulator-stage5-production-ux
    xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab \
      -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath "$PWD/.artifacts/final-build" CODE_SIGNING_ALLOWED=NO build analyze

Each installed-shell mode includes the entire A/B proof, so Stage1 alone need not be repeated. WebKit mode now includes eleven live tests (53 with inherited tests), including remaining redirect/Location, decoded gzip/header/escaped-reply boundaries and streaming deadline vectors. Individual commands may take minutes; use a bounded background process on hosts with short foreground caps, retain its handle and verify its real exit/cleanup. Do not abandon an owned Simulator after a tool timeout. Current exact-source results are retained in `docs/integration/final-candidate-evidence.json` when produced and the same-card review handoff; absence of that record means final-source verification is pending. No runner grants independent review, product acceptance or an owner RC decision.

## Explain v2 runtime acceptance

    scripts/verify simulator-explain-v2

This bounded mode creates one owned iPhone Simulator and reuses the production
loopback lab, installed-app hash proof and cleanup contract. It runs the real built
A and B assets in focused WKWebView layout tests at 320×740, 390×844 and 1100×900,
plus reduced-motion and enlarged-text coverage. It then installs one production
shell and proves unchanged A, served B, real catalog/quote values, cold B/repeat,
API unavailability/retry, missing-entry fallback/recovery, native safe areas and an
accessibility-extra-large installed-shell pass. Static-port control files coordinate
the XCTest runner but never supply API results or inject JavaScript into the installed
app. Result bundles retain screenshots, geometry and accessibility trees.

The mode rebuilds served assets but does not rebuild or reinstall the native app
between A and B. It records exact installed-file equality, built asset hashes,
attributable backend events, fault facts and teardown under a fresh ignored
`.artifacts/verify-simulator-explain-v2-*/` directory. The run remains Simulator-only
and synthetic; it is not independent acceptance or release authorization. See the
[Explain v2 runtime evidence](docs/design/explain-v2/runtime-evidence.md) and its
[machine-readable ledger](docs/design/explain-v2/runtime-evidence.json).

## Actual Simulator A/B proof (Stage 1 only)

After the core command:

    scripts/verify simulator-stage1

This creates one dedicated `PER85-Stage1-*` Simulator using an available iOS runtime, runs the existing iOS Simulator suite, builds the app and a separate XCTest UI runner, and installs the real shell. It serves variant A on port 8787 with the API on 8788, submits catalog GET through the actual React UI, then rebuilds only served web assets to B and taps native Reload. The same running application submits quote POST and displays the nested response total. There is no native build/install/relaunch between the observations.

The UI runner's separate URLSession accesses only `/stage1/*.txt` on the static web port for host coordination; it never requests an API fixture, supplies result data, evaluates JavaScript or substitutes a bridge. These control files live in ignored build output, not the production web bundle. Backend method/path/tag logs attribute the catalog and quote requests; production CSP blocks browser connections and the shipped web client has no fetch fallback.

Before A, after A and after B, the host records the actual installed container and a sorted SHA-256 map of every regular `.app` file (including hidden files; unexpected symlinks fail closed). Container, UDID and every file hash must remain identical. A/B asset hashes, actual XCTest assertions/screenshots, result bundles, logs and cleanup records are under `.artifacts/verify-simulator-stage1-*/`. Hashes vary with build path; only equality within a run is expected.

The runner refuses occupied ports without killing foreign listeners. It stops its own lab, verifies both ports can bind again, shuts down/deletes only its newly created Simulator and verifies its absence on success or handled failure. SIGINT/SIGTERM trigger cleanup; a force-kill or host crash cannot be guaranteed recoverable automatically. Do not run simultaneous fixed-port sessions. If cleanup fails, read `cleanup.json` and use the recorded state directory/UDID; never broadly kill Node or Simulator processes.

Stage 1 was a coordinator checkpoint, not final acceptance. The final matrix above reconciles subsequent error/security/lifecycle proof; independent integration review and separate exact-RC acceptance remain separate gates. There is no generic `simulator` command. See [Stage 1 evidence](docs/integration/STAGE1.md), [verification obligations](docs/verification-plan.md), and active [OpenSpec tasks](openspec/changes/add-bridge-lab/tasks.md).

## Actual Simulator outcome slice (Stage 2, incomplete matrix)

    scripts/verify simulator-stage2-outcomes

Includes the complete Stage1 regression, then replaces only served assets with an opt-in test-only React page (`web/acceptance/`). It imports the production bridge client and business interpreters and runs inside the same clean installed shell through real WebKit and native URLSession. Neither normal A/B build includes this entry; no native test bypass or browser fetch is used. This proves the integrated transport/interpreter path, not the production Diagnostics layout or accessibility.

The UI test asserts preserved HTTP 503/422 bodies, business and JSON-parse classification, native timeout, explicit cancellation and acknowledgements, out-of-order concurrent correlation, and NETWORK_ERROR after actually stopping the backend. The host requires matching backend events, connection-close for timeout/cancel with no late success, unchanged installed app files, released ports and removed owned Simulator. All failure categories are assertions, not skipped tests. Test-runner synchronization remains restricted to static web-port control files.

This is an outcome-only mode, not an approved RC. Other modes supply iframe provenance, redirects, synthetic privacy, bounds and revocation as mapped in the final matrix. See [Stage2 outcome evidence and gaps](docs/integration/STAGE2_OUTCOMES.md). `final_acceptance` remains false.

## Actual Simulator trust/limits slice (Stage 3, incomplete matrix)

    scripts/verify simulator-stage3-trust-limits

Repeats production A/B, then exercises raw closed/version/session/id validation,
exact raw/Unicode request and chunked response size boundaries, URL/header policy,
same/cross/loop redirects with zero destination hits, media/encoding rejection,
inert hostile response text, and eight native admissions/ninth BUSY through the
unchanged installed shell. Host logs corroborate actual request outcomes and reject
forbidden effects. Same/foreign frame attempts are blocked by the unchanged
production CSP BEFORE bridge execution; this is not handler-provenance proof.
The test-only raw probes intentionally bypass TS validation, never native policy.

See [Stage3 evidence and remaining obligations](docs/integration/STAGE3_TRUST_LIMITS.md).
This mode does not repeat Stage2 outcome probes; both commands remain available.
Provenance/privacy/revocation, production Diagnostics and adversarial cleanup are
covered by the complementary modes; no single mode is final security acceptance.

## Real WebKit component trust/lifetime/privacy (Stage4)

    scripts/verify simulator-stage4-webkit-privacy

Runs eleven live WebKit/network component tests plus42 existing Simulator tests on
a newly created dedicated Simulator. The opt-in fixture has no CSP so actual
same/foreign iframe messages reach the unchanged production adapter. This is NOT
the installed React E2E layer. It checks real navigation, reload, provisional
failure, close/destruction socket cancellation and fresh-id isolation, plus strictly
synthetic native/WK cookies, cache and authentication challenges. The actual
production model's nonpersistent WK store is also exercised. No real credentials
or host keychain are read. Owned fixture ports8787/8788 and the device are cleaned
on success or handled failure. Run fixed-port modes serially.

See [Stage4 evidence and explicit framework seams](docs/integration/STAGE4_WEBKIT_PRIVACY.md).
Production Diagnostics and adverse runner lifecycle are separate modes below;
none of these commands constitutes final acceptance.

## Production Diagnostics and adverse operations (Stage5)

    python3 scripts/tests/operations.py
    scripts/verify simulator-stage5-production-ux

Run these serially after `scripts/verify unit`. The UI mode repeats A/B and then
uses the actual production Diagnostics controls: HTTP status/body, business/JSON
errors, native timeout, visible loading and independent slow cancellation with the
fast result preserved. The slow diagnostic now waits10s (15s native deadline),
giving the user time to cancel. It does not load the opt-in acceptance React page.

Explain v2 moves these controls out of the participant journey into the opt-in
`?mode=diagnostics` surface. The browser URL is explanatory only: a normal browser
has no native bridge. In the installed app, long-press the native footer labelled
`Версия приложения <short version> · сборка <build>` and choose `Диагностика`
(`lab.openDiagnostics`), or use the equivalent named VoiceOver action. Version and
build come from the installed Bundle; a missing value is labelled unavailable rather
than invented. Native reload and failed-load retry preserve the selected fixed
destination. `Вернуться к демо` (`lab.openDemo`) loads the fixed demo root.

The shell disables web interaction until the selected top-level document finishes.
A load failure revokes that document, keeps stale content non-interactive, and shows
a native error with `Повторить` plus a return-to-demo path when Diagnostics was
selected. The reviewed N candidate passed the unchanged Stage4 and Stage5 commands. The R
candidate adds focused Explain runtime/layout evidence and proportional Stage2/3
regressions. Independent R review and the historical original Astra/xhigh technical
acceptance passed on `6ef85571005bb42c7f3bd6e3be6158d338f4b0c1`. Later PR-review
corrections are subject to independent verification and external review on the current
exact head before publication; historical runs are not relabeled as execution on a
newer commit. Owner product/aesthetic acceptance remains separate. See
[Explain v2 native evidence](docs/design/explain-v2/native-evidence.md) for the exact
N scope and [Explain v2 runtime evidence](docs/design/explain-v2/runtime-evidence.md)
for the R scope, executed gates and deliberate limits.

The operations gate deliberately interrupts fresh owned runner processes before
and after service ownership, injects a failing command, checks actual service
signals with active work and repeat start/stop, and proves a synthetic foreign
listener survives occupied-port refusal. Expected child failures must still yield
an overall gate PASS and verified cleanup. Only newly created process groups,
canonical owned lab state and recorded dedicated Simulators may be stopped.
The runner marks its unique lab state cleanup-eligible before the interruptible start
command; a deterministic regression covers that ordering, while the operations gate
covers cleanup after startup and service ownership. SIGKILL and host crashes remain
outside automatic recovery guarantees; see
[Stage5 evidence, recovery and limits](docs/integration/STAGE5_UX_OPERATIONS.md).
The final matrix and observed candidate evidence distinguish full exact-source
regression from the still-independent review/acceptance gates.

## Manual demonstration

    npm ci --prefix web
    npm --prefix web run build:a
    scripts/lab start
    scripts/lab status

Build with the checked-in project, using a dedicated Simulator you own (replace the placeholder with its actual UDID):

    xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab \
      -destination 'platform=iOS Simulator,id=<owned-UDID>' \
      -derivedDataPath "$PWD/.artifacts/manual-derived" CODE_SIGNING_ALLOWED=NO build
    xcrun simctl install <owned-UDID> .artifacts/manual-derived/Build/Products/Debug-iphonesimulator/BridgeLab.app
    xcrun simctl launch <owned-UDID> lab.webnative.BridgeLab

In A, tap `Получить каталог`. The result displays the actual returned title/SKU.
The presenter then runs `npm --prefix web run build:b` separately; only completed
served web assets are replaced. The participant taps `Загрузить обновлённый экран`,
which performs a same-origin document reload. In B, tap `Рассчитать заказ`; the
receipt uses the returned quantity, minor units and currency. Keep the app installed
throughout. A never exposes quote in the main demo; a cold B starts directly with
quote and does not invent A history. Open Diagnostics through the native footer
mechanism described above, not through a visible web-demo button.
Finish with:

    scripts/lab stop
    scripts/lab status
    xcrun simctl shutdown <owned-UDID>

Stopped status intentionally exits 1 and prints `state: stopped`. Manual builds replace tracked `web/dist` (variant B is the reviewed committed default); do not confuse generated differences with source changes. For isolated lifecycle overrides and ownership semantics see [backend README](backend/README.md). Always use identical options for start/status/stop and stop before deleting a worktree.

## Boundaries and source of truth

- [Approved mission](docs/agent/OWNER_MISSION.md), [architecture](docs/architecture.md), [normative v1 protocol](protocol/v1/README.md).
- `native/TransportPackage/`: generic Foundation HTTP, no business endpoints/models.
- `ios/`: shell, frame/origin/lifecycle adapter and tests; page 127.0.0.1:8787 and API 127.0.0.1:8788 are separate fixed policies.
- `web/`: React client, scenarios, interpretation and UI.
- `backend/` and `scripts/lab`: synthetic fixtures and opt-in lifecycle.
- `scripts/verify`: reproducible integration evidence, not an approval mechanism.

All services bind loopback, use no real credentials and are explicitly opt-in. Production trust, real device networking, OS/framework internal buffering and server-side rollback of cancelled work are not solved by this lab.
