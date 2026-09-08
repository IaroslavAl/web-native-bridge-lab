# Stage3 — bounded installed-shell trust and limits checkpoint

Status: unit gate and actual Simulator trust/limits run PASS; intermediate implementation evidence only. This is not an approved RC or complete task6.3. Coordinator inspection, eventual independent same-card integration review, separate exact-RC acceptance and the remaining matrix are still required. No production native, backend, client, interpreter, App, policy or protocol source was changed.

## Reproduce

    scripts/verify unit
    scripts/verify simulator-stage3-trust-limits

The new mode extends the existing runner, not a parallel framework. It owns a fresh dedicated Simulator and loopback lab on 8787/8788, repeats the existing 42 Simulator tests and production catalog A → web-only quote B proof, then replaces only served assets with the opt-in acceptance React page. `SameBinaryTests.testWebOnlyUpdateOnSameInstalledApplication` selects the trust button using a static test-runner control marker. Normal A/B builds exclude the test entry. The installed shell remains the production shell, with no XCTest bundle, injected script or fake executor.

Unlike the outcome page, `web/acceptance/trust.ts` deliberately sends raw wire inputs using the production WebKit boundary. This bypasses the TS client's validation, NOT native validation, and permits malformed/non-string inputs to reach actual `WKScriptMessageHandlerWithReply`. Replies are asserted inside real WebKit, and XCTest asserts the resulting React accessibility text. Network successes and failures come from the real native URLSession and unchanged backend. No browser fetch, arbitrary native test endpoint or policy relaxation is present. The UI runner only accesses static web-port coordination files.

Stage2 remains separately reproducible with `scripts/verify simulator-stage2-outcomes`; Stage3 repeats A/B but does not rerun its outcome probes or claim its backend-off NETWORK_ERROR assertion. Both modes stop the actual owned backend; only Stage2 then submits an error probe.

## Newly observed evidence, by layer

| Requirement / scenario | Actual Stage3 assertion | Layer and limitation |
| --- | --- | --- |
| WB-01 / T-WIRE | Numeric2, string1, null, Boolean and missing version → UNSUPPORTED_VERSION; invalid JSON, array, non-string input, extra field → INVALID_REQUEST; closed bounded error fields/id asserted | Real installed-shell WebKit/native; not schema-only |
| WB-01 / WB-03 | Invalid id0/negative/fraction/overflow/Boolean → null-id INVALID_REQUEST; malformed/missing token and extra field rejected; wrong well-shaped request/cancel token → ORIGIN_DENIED with recoverable id | Main trusted frame; a wrong token is not proof of foreign frame provenance |
| WB-03 / T-CORRELATION | Same id remains usable after structural/session errors; completed duplicate denied, repeated hello retains token and high-water mark; completed raw cancelAck false | Real native engine via installed shell; token is never retained in evidence |
| HT-01 / HT-05 | POST text body of 16384 emoji = 65536 UTF-8 bytes echoed exactly; plus ASCII byte → REQUEST_TOO_LARGE with no backend hit | Actual opaque Unicode HTTP echo; client-side JS code-unit count is not substituted |
| WB-01 / HT-05 | Valid hello padded to 131072 raw UTF-8 bytes accepted, +1 → MESSAGE_TOO_LARGE id null; Unicode raw message with JS length below cap but bytes above cap also denied before structural error | Actual WebKit raw message boundary |
| HT-03 / T-POLICY | Localhost, web port, HTTPS and omitted port → URL_DENIED; relative/userinfo/fragment/encoded control/invalid escape → INVALID_REQUEST; Authorization/Cookie/Host/mixed-case/CRLF/129-char values denied | No remote URLs used; host log forbids health destination requests during the probe interval |
| HT-03 / T-REDIRECT | Same-origin302, cross-origin302 and loop307 each return REDIRECT_DENIED | Backend source hit exactly once each; zero catalog/health destination hits even without tags; loop source never repeated |
| WB-03 / WS-02 text subset | Quotes, slash, newline, script/img markup, emoji and Unicode separators echoed unchanged and rendered as React text; title/URL unchanged and no injected image element | Test page rendering, not production Diagnostics UI; production CSP remains active |
| HT-05 / T-BOUNDS | Actual no-Content-Length chunked1048576 body accepted unchanged; 1048577 → RESPONSE_TOO_LARGE; binary → UNSUPPORTED_RESPONSE; invalid UTF-8 → RESPONSE_ENCODING | Existing real HTTP fixtures; does not measure OS/decompressor buffering or cancellation timing on overflow |
| HT-05 / HT-06 | Eight native delay requests admitted, ninth → BUSY before any of eight completed; duplicate active id denied without replacing original; all eight unique id/tag/body responses arrive | Host requires all eight actual tagged delay completions exactly once and zero ninth/duplicate request hit; not merely eight JS Promises. URLSession may limit simultaneous sockets below native admission capacity |
| WB-02 / frame prevention subset | Same-origin and foreign-origin iframe attempts emit actual frame-src CSP violations; no corresponding backend destination request; current main-frame session retained | Denied BEFORE bridge execution. Neither frame loads or invokes the handler; this does NOT prove real foreign/same-origin iframe handler provenance checks |
| WS-01 / WS-03 regression | Production catalog GET and quote POST after web-only rebuild, actual business UI results and identical installed full manifest/container | Same installed shell before/after trust probes as well |
| LL-02 cleanup subset | Owned lab stop/status, port rebind, own Simulator shutdown/delete and absence | Ordinary handled run only; adversarial signals/foreign-port preservation still pending |

`require_stage3_events` takes only the interval after production B and before stop/status health requests. It rejects redirect destinations regardless of retained request tags, duplicate redirects, missing required events and unadmitted s3-tagged requests. Unit tests first failed for the missing helper, then passed with positive, every-missing-event, duplicate/loop, untagged destination, BUSY, rejected-body and frame-destination mutations. This is test infrastructure TDD; no production feature was added to make the integration probes pass.

## Durable provenance

`stage3-trust-limits-evidence.json` retains command/exit records, source provenance, test totals, tool/runtime data, exact installed/app and web manifests, sanitized backend interval, actual UI assertion transcript and cleanup. No session tokens, cookie/credential stores or unrelated environment are collected. Raw ignored `.artifacts/verify-*` directories are disposable, not the sole evidence.

The first Stage3 run executed the working-tree candidate over `fb3baba425873bef364e0146d289444181131912`; all five code/test files were written before both gates and unchanged through commit. Evidence names the subsequent source commit and its exact changed-file SHA256 map, without pretending the runner started on a clean committed HEAD. The evidence-only commit follows. Module parent identities remain ancestors. No primary-main update, archive, publication, graph/profile/runtime change or child agent is involved.

## Remaining mandatory gaps, not waived

- WB-02 actual handler invocation with real foreign-origin and same-origin iframe WebKit metadata; precommit/inactive provenance and real denied main navigation/new-window behavior. The inherited42 Simulator tests primarily use adapter/core seams, not loaded malicious WebKit documents. Stage3 CSP prevention is not a substitute. A bounded component-host test document with actual WebKit metadata can cover handler provenance without altering production policies; label that layer separately.
- WB-01/WB-03 actual same-URL reload fresh token and queued stale-token ingress, id exhaustion and malformed-reply client cases beyond inherited unit coverage.
- HT-03 all other redirect statuses301/303/308, missing/malformed Location, more URL canonicalization vectors and exact8192 URL /128 value boundaries in real integration. Current same/cross/loop routes are covered, not the entire redirect status matrix.
- HT-05 exact8192/+1 exposed response-header bound, escaped outgoing reply above incoming cap, compressed decoded overflow, slow-trickle native monotonic deadline, min/max deadline integration, additional Unicode exact raw boundaries and unexposed-header filtering under actual network. Do not relabel unit doubles as full E2E.
- HT-04 isolated synthetic cookie/credential/cache/challenge tests; no real credential store access. Deferred by the Stage3 packet.
- WB-04 full live reload/navigation/provisional failure/close/termination/teardown with delayed old network completion, fresh id1 and no stale UI contamination. Deferred by the packet.
- HT-01 additional query/POST edge cases and HT-02 actual empty204. Production Diagnostics UX/error/loading/cancel isolation and safe rendering remain later obligations; the acceptance page is not the production UI.
- LL-02 runner SIGINT/SIGTERM/adversarial child cleanup, occupied fixed-port foreign process preservation. Normal cleanup is not this proof.
- LL-03 complete matrix/spec reconciliation, independent integration review, exact-RC acceptance and owner RC handoff.

Simulator only, synthetic loopback HTTP, no production security claim. Session-generation token is not authentication. OS/framework buffering and rollback of cancelled server work are unmeasured. Xcode warnings may occur; no warning-free Xcode claim. Astra/openai-codex session/card routing observed, high effort declared in coordinator packet but effective effort not independently tool-visible.

The coordinator-owned `PER85_COORDINATOR_CHECKPOINT` hold applies to the same card/run after cleanup and commit. No incomplete-task self-completion or premature final review is requested.
