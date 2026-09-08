# Stage5 — production Diagnostics and owned adverse operations

This is a bounded integration checkpoint, NOT a reviewed RC or final acceptance.
Entry: `da1ce2c1f16d54178396b867399cd47250ef62e8`. Observed commands, exact source hashes, failures and cleanup are retained in `stage5-ux-operations-evidence.json`.

## Reproduce (serialized fixed ports)

    scripts/verify unit
    python3 scripts/tests/operations.py
    scripts/verify simulator-stage5-production-ux

Python helpers use ephemeral ports and never recursively invoke the full suite. The explicit operations gate owns ports8787/8788 and fresh dedicated Simulators; do not overlap it with any other fixed-port mode. Its deliberate child failures are expected, but the gate itself must exit0. All raw artifacts remain under ignored `.artifacts/`; this document and the evidence JSON are durable.

## Product behavior and layers

- WS-01/WS-03: the existing real XCUI A/catalog → served-web-only B/quote sequence remains. Installed UDID, container and complete app manifest must be identical through production Diagnostics. No test-only React entry, injected JavaScript, browser API fallback or native result stub is used in this mode.
- WS-02: real production buttons render the exact HTTP503 opaque JSON body, business OUT_OF_STOCK, JSON-parse error and native TIMEOUT. The existing concurrent controls show loading and an enabled Cancel; cancel closes only the slow socket, displays CANCELLED, preserves fast10ms and settles loading/Cancel. Backend events independently corroborate each result and prohibit slow late200.
- The first actual UI run passed all error categories but failed its loading query. The initial timing hypothesis was incomplete: after lengthening the diagnostic, a second run still failed because WebKit exposes `1`, `request` and `loading` as THREE static-text nodes, not one combined label. The retained live accessibility tree confirms this; the test now matches the actual `loading` node. The web-only adjustment to the existing slow diagnostic10s (native deadline15s) gives a human time to observe and cancel, but is not claimed to fix the accessibility-query mistake. No new control/endpoint/policy or protocol limit was added. A focused web assertion went RED on1000/5000 before changing to10000/15000.
- Real HTTP JSON punctuation is displayed as opaque text. Hostile HTML/script injection in the exact production App error panel is separately asserted by a clearly mocked-boundary React DOM test. Existing Stage3 real hostile-text transport/render evidence remains complementary, NOT production-UI hostile-input proof. Existing product controls cannot request the echo endpoint; no feature was added just to manufacture that coverage.

## Owned operations and fixes

- LL-02/LL-03: actual SIGINT during a fresh Simulator boot before services, SIGTERM during boot with a real WebKit fixture owning both ports, and an intentionally failing xcodebuild executable after real fixture/device ownership must produce exit1/failure evidence, remove only the owned Simulator and release both ports. The failing executable is a test-only command-boundary fault, not fabricated successful Xcode output.
- Actual lab start/repeated start, verified service SIGINT/SIGTERM with an active delayed HTTP socket, stop/repeated stop/stopped status exercise the unchanged lab/server implementation. Identity is re-read through canonical lab status immediately before signalling the freshly created service.
- A fresh synthetic foreign listener must survive both runner preflights with identical PID/start identity and response; no Simulator may be created. It is stopped only after preservation assertions, as the operations test's own resource.
- Real regression controls exposed a runner defect: command timeout/nonzero exit killed only the direct child, leaving a grandchild listener. Commands, UI test runner and WebKit fixture now use newly created sessions and tracked Popen handles; cleanup terminates their owned group, escalates after2s, reaps the direct child and verifies no live group members after escalation. Detached lab services remain governed by lab's separate verified state, not arbitrary group discovery.
- A first group-cleanup attempt exposed two timing issues: Darwin `killpg(group,0)` returned EPERM while the last member exited (reproduced20/20 with fresh sleep processes), and SIGKILL delivery was asynchronous relative to the port assertion. Numeric ps group/state readback now distinguishes live members from zombies, waits for actual disappearance and propagates real permission failures. No foreign group is selected from a PID scan.
- Cleanup intent is recorded before lab-start, so a failed/interrupted start can still invoke the original state-bound stop. No Hermes runtime, approvals, profiles, unrelated processes or primary checkout changed.

## Deliberate limits and remaining gate

All evidence is Simulator/synthetic loopback only. SIGKILL/host crash cannot execute Python finally. Recovery requires the exact recorded state directory/options with `scripts/lab stop`, and shutdown/delete of only the recorded owned UDID after identity inspection; never kill all Node/Simulator processes. Do not delete the worktree before owned services stop.

Tests cover the named ownership checkpoints, not every instruction-level interruption window, repeated signals during cleanup, child processes deliberately escaping into new sessions, or malicious same-user state/PID forgery. Direct CLI interruption in the tiny spawn→ownership-state-write window is not independently exercised here; do not infer that guarantee from service-signal tests. Retained state and strict ownership checks remain necessary recovery boundaries.

Next: exact final-source full regression across Stage1–5, per-layer vector/traceability reconciliation (including Stage3 low-level HTTP/header/encoding/redirect/deadline obligations), independent same-card integration review, separate exact-RC acceptance and owner handoff. Stage4's actual OS WebContent termination and exhaustive framework scheduling gaps remain explicitly documented there. OpenSpec6.3/6.4 and final acceptance remain unchecked; no archive/main/publication is authorized by this checkpoint.
