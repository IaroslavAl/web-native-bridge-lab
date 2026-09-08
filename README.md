# Web–Native Bridge Lab — PER-85

A small Simulator-only foundation: remotely served React constructs requests and parses business JSON; a generic Swift transport executes HTTP through the production WKWebView adapter. This is not production-ready. Only synthetic loopback data is supported; no authentication, cloud service, device signing or publication.

## Prerequisites

macOS with Xcode and an installed iOS Simulator runtime; Node >=20.19 (tested Node 26.5), npm, Python 3.9+, Swift/Xcode command line tools, and `/usr/sbin/lsof`. Dependencies are pinned under `web/` and `openspec/tooling/`; no global install, approvals-policy change or service registration is needed.

## Core verification

From this checkout:

    scripts/verify unit

Installs pinned local tooling, audits the complete web dependency tree, runs schema/OpenSpec validation, backend HTTP/process tests, native and iOS package tests, React/TypeScript tests and both web builds. Output goes to a fresh ignored `.artifacts/verify-unit-*/` directory. Commands and exit codes are recorded in `commands.json`; failures return nonzero. Builds use isolated output and do not replace tracked `web/dist`. Unit native/bridge doubles are not proof of actual WebKit networking.

## Actual Simulator A/B proof (Stage 1 only)

After the core command:

    scripts/verify simulator-stage1

This creates one dedicated `PER85-Stage1-*` Simulator using an available iOS runtime, runs the existing iOS Simulator suite, builds the app and a separate XCTest UI runner, and installs the real shell. It serves variant A on port 8787 with the API on 8788, submits catalog GET through the actual React UI, then rebuilds only served web assets to B and taps native Reload. The same running application submits quote POST and displays the nested response total. There is no native build/install/relaunch between the observations.

The UI runner's separate URLSession accesses only `/stage1/*.txt` on the static web port for host coordination; it never requests an API fixture, supplies result data, evaluates JavaScript or substitutes a bridge. These control files live in ignored build output, not the production web bundle. Backend method/path/tag logs attribute the catalog and quote requests; production CSP blocks browser connections and the shipped web client has no fetch fallback.

Before A, after A and after B, the host records the actual installed container and a sorted SHA-256 map of every regular `.app` file (including hidden files; unexpected symlinks fail closed). Container, UDID and every file hash must remain identical. A/B asset hashes, actual XCTest assertions/screenshots, result bundles, logs and cleanup records are under `.artifacts/verify-simulator-stage1-*/`. Hashes vary with build path; only equality within a run is expected.

The runner refuses occupied ports without killing foreign listeners. It stops its own lab, verifies both ports can bind again, shuts down/deletes only its newly created Simulator and verifies its absence on success or handled failure. SIGINT/SIGTERM trigger cleanup; a force-kill or host crash cannot be guaranteed recoverable automatically. Do not run simultaneous fixed-port sessions. If cleanup fails, read `cleanup.json` and use the recorded state directory/UDID; never broadly kill Node or Simulator processes.

Stage 1 is a coordinator checkpoint, not final acceptance. Full real error/security/lifecycle matrix, same-card independent integration review and separate exact-RC product acceptance are still required. No generic `simulator` command is advertised as a full gate until that matrix is implemented. See [Stage 1 evidence](docs/integration/STAGE1.md), [verification obligations](docs/verification-plan.md), and active [OpenSpec tasks](openspec/changes/add-bridge-lab/tasks.md).

## Actual Simulator outcome slice (Stage 2, incomplete matrix)

    scripts/verify simulator-stage2-outcomes

Includes the complete Stage1 regression, then replaces only served assets with an opt-in test-only React page (`web/acceptance/`). It imports the production bridge client and business interpreters and runs inside the same clean installed shell through real WebKit and native URLSession. Neither normal A/B build includes this entry; no native test bypass or browser fetch is used. This proves the integrated transport/interpreter path, not the production Diagnostics layout or accessibility.

The UI test asserts preserved HTTP 503/422 bodies, business and JSON-parse classification, native timeout, explicit cancellation and acknowledgements, out-of-order concurrent correlation, and NETWORK_ERROR after actually stopping the backend. The host requires matching backend events, connection-close for timeout/cancel with no late success, unchanged installed app files, released ports and removed owned Simulator. All failure categories are assertions, not skipped tests. Test-runner synchronization remains restricted to static web-port control files.

This is a bounded outcome checkpoint, NOT the complete security/lifecycle matrix or an approved RC. Remaining proof includes real iframe/foreign-origin provenance, redirect destination non-delivery, synthetic credential isolation, bounds/adversarial wire inputs and live document-revocation races. See [Stage2 outcome evidence and gaps](docs/integration/STAGE2_OUTCOMES.md). `final_acceptance` remains false.

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

Tap “Send through native HTTP”: catalog shows `Notebook (notebook) — total 1`. Then run `npm --prefix web run build:b`, tap native Reload and submit again: quote shows `notebook × 2 — USD 1200 minor units`. Keep the app installed throughout. Both variants also expose the scenario selector and Diagnostics. Finish with:

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
