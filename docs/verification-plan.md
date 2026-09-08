# Verification plan and requirement-to-test matrix

Status: planned runtime tests, not executed product evidence. Foundation validates only OpenSpec shape, schema and example classifications. Stable test case IDs below are implementation obligations, not claims that files or tests already exist. Module reviewers replace planned references with actual test names/commands in their handoffs. Final integration evidence maps every row to exact RC tests; missing or skipped mandatory behavior is a failure, not a pass.

Sources: approved owner mission, active OpenSpec `add-bridge-lab`, normative `protocol/v1/README.md`, and architecture fixture/build/lifecycle decisions. Contract text plus schema are reviewed together; a green schema cannot prove network policy or WebKit provenance.

## Requirement → scenario → executable test plan

| Requirement | Scenario coverage / test case IDs | Execution level and owner | Foundation status |
| --- | --- | --- | --- |
| HT-01 | T-HTTP: GET encoded query, allowed headers, POST JSON opaque bytes, POST text exact echo; production native business-model scan | Swift executor tests; backend fixtures; real Simulator A/B | Planned |
| HT-02 | T-OUTCOME: 503/422 preserve body/status; 200 malformed JSON unchanged; 204 empty; connection refused is NETWORK_ERROR | Swift + web unit; real fixtures/Simulator | Planned |
| HT-03 | T-POLICY: foreign/alternative host, port, HTTPS, omitted port, relative URL, userinfo, fragment, backslash, invalid/encoded-control escapes; forbidden/mixed-case/CRLF headers; GET body/POST type; T-REDIRECT same/cross/loop plus every denied redirect status and missing/malformed Location, destination hit count zero | Swift injected network/loopback; real redirect probes and backend logs | Planned |
| HT-04 | T-PRIVACY: synthetic shared cookie/credential/cache resources not used; Set-Cookie/X-Private filtered; auth challenge cancelled without prompt | Swift isolated session tests; /fixtures/headers on Simulator | Planned |
| HT-05 | T-BOUNDS: exact and +1 request/raw/response/header sizes, Unicode byte counts, URL/value caps; min/max/invalid deadline and slow-trickle timeout; 8 accepted/9th BUSY; no-length chunked and compressed decoded overflow; binary/invalid UTF-8; incoming cap not incorrectly applied to escaped reply | Swift tests with controlled clock/chunks and isolated local HTTP; bridge raw-cap test; real large/delay/encoding fixtures | Planned |
| HT-06 | T-RACES: cancel wins/response wins/timeout wins, duplicate/late callbacks, unknown/completed cancel, active duplicate id; slow/fast out-of-order completion exactly once | Swift deterministic scheduler/seams; TS client tests; real delayed cancel/concurrency | Planned |
| WB-01 | T-WIRE: request/cancel/response/error/ack shapes; unknown fields, version 2/string/missing, invalid JSON/non-string/id/oversize, ordered errors and recoverable/null id | Shared schema vectors plus adapter unit; real WebKit invalid message probes | Schema vectors runnable; adapter planned |
| WB-02 | T-ORIGIN: exact committed main frame accepted, foreign origin and same-origin iframe denied, precommit/inactive denied; request allowlist remains separate; external navigation/new-window denied without opening apps | Adapter policy unit plus real WKWebView frame/navigation tests | Planned |
| WB-03 | T-CORRELATION: monotonic ids/gaps/exhaustion, active/completed duplicate no replacement, cancel own Promise and original terminal, quotes/script/Unicode delivered as data, malformed/mismatched reply local PROTOCOL_ERROR | Adapter + web unit; real WebKit structured reply tests | Planned |
| WB-04 | T-REVOKE: reload/new navigation/provisional failure/close/termination/teardown; new id 1 unaffected by old completion; handler/task/deadline cleanup, rejected navigation leaves old document intact | Adapter race tests; real WKWebView reload/close/iframe tests | Planned |
| WS-01 | T-CATALOG: books list/empty category; T-QUOTE: quantity 2 total 1200 and invalid quantity 422; verify requests originate in native and business parse only in React | React tests (mock explicitly labeled), API fixture tests, actual Simulator A/B | Planned |
| WS-02 | T-UX: loading/result/HTTP/business/parse/transport/timeout/cancel distinct; no bridge → no fetch; two pending states and cancel isolation; response text rendered safely | React component/client tests; real Diagnostics fixtures | Planned |
| WS-03 | T-SAME-BINARY: visible A catalog then B quote after only web rebuild/reload, changed web hashes, identical installed executable AND sorted .app file manifest hashes before/after; no native build/install between | Integration then independent exact-RC Simulator acceptance | Planned |
| LL-01 | T-FIXTURES: every architecture route plus invalid query/POST/unknown route/wrong method; CSP/cache/CORS; missing dist 503; rebuild read fresh; traversal/symlink escape refused | Backend automated real HTTP tests using temporary ports/assets | Planned |
| LL-02 | T-LIFECYCLE: start/status/stop from another cwd; repeated and concurrent start/stop; healthy/stale/conflict states; PID reuse; foreign bind; partial second-bind failure; delayed sockets and tracked-child shutdown; status/assets distinction; released ports | Backend process-level tests with isolated state/ports; integration teardown rerun | Planned |
| LL-03 | T-REPRO: fresh checkout/tool install/build/gates, complete matrix with actual names and exact head, independent same-card reviews and final verifier; active unchecked work cannot be archived as done | Integration, independent acceptance, coordinator reconciliation | Planned |

Boundary cases must assert the actual field/code and absence of forbidden effects (network start, redirected destination hit, second reply, foreign process signal), not merely a nonzero exit. Unit mocks support repeatable races but do not prove real NSURLSession/WebKit behavior.

## Foundation commands available now

Run from the assigned repository root (Node >=20.19.0):

    npm ci --prefix openspec/tooling --ignore-scripts --no-audit --no-fund --cache "$PWD/.artifacts/npm-cache"
    OPENSPEC_TELEMETRY=0 OPENSPEC_NO_COMPLETIONS=1 openspec/tooling/node_modules/.bin/openspec validate --all --strict --no-interactive --json
    OPENSPEC_TELEMETRY=0 OPENSPEC_NO_COMPLETIONS=1 openspec/tooling/node_modules/.bin/openspec status --change add-bridge-lab --json
    node protocol/v1/validate.cjs
    git diff --check

Official OpenSpec 1.12.0 is pinned in openspec/tooling/package-lock.json. Initialization was `openspec init . --tools none --language English --profile core --no-animation --no-copilot-cloud`, followed by `openspec new change add-bridge-lab --schema spec-driven --json`. The CLI warned that no-copilot-cloud was ignored with no Copilot tool; no tool/profile integration was selected. CLI schema templates/instructions were inspected, not inferred. First-party reference: https://github.com/Fission-AI/OpenSpec/blob/main/docs/cli.md (consulted for this foundation). No global install/config change is required. OpenSpec artifact-complete status means the four draft files exist, NOT that implementation or review tasks passed.

`validate.cjs` compiles the actual schema with pinned Ajv, asserts labeled valid/invalid examples, and verifies semantic-only vectors are structurally valid. It deliberately does not implement runtime policy. Semantic examples have expected codes for native/adapter tests to import; this foundation does not claim those codes were produced by a transport.

## Downstream command contracts (not executable in this foundation)

Each module publishes exact commands after implementation; these names are the agreed entry points:

- Backend: `node --test backend/tests/*.test.mjs`; scripts/lab interface from architecture. Backend tests use .mjs and Node built-in test runner.
- Transport: `swift test --package-path native/TransportPackage`.
- Web: `npm ci --prefix web`, `npm --prefix web test -- --run`, `npm --prefix web run build:a`, `npm --prefix web run build:b`. Web worker selects/pins compatible test packages; test script must support --run.
- iOS: `xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab -destination 'platform=iOS Simulator,id=<dedicated-UDID>' -derivedDataPath <workspace>/.artifacts/DerivedData CODE_SIGNING_ALLOWED=NO test`; worker records available runtime/device and exact command/output. No invented UDID or signing setup.
- Integration: `scripts/verify unit` and `scripts/verify simulator --udid <dedicated-UDID>` must fail honestly on missing prerequisites, save command results, and clean up owned resources on success/failure/signals. Simulator command owns serial fixtures + A/B proof, not another permanent server. Native project can add a separate UI test scheme if needed, documented without changing product behavior.

The matrix's behavioral test cases are stable; framework-specific test method names can vary. Tests must not mutate other worktrees or run shared fixed-port services in parallel. No network package install failure can be replaced by fabricated fixture results.

## Real WebKit security probes

T-WIRE/T-CORRELATION also cover hello/helloAck, missing/malformed session, repeated hello with unchanged token/high-water mark, fresh token after same-URL reload, and queued stale-token request/cancel denial before id consumption. These are actual adapter/WebKit obligations, not proven by the schema vectors alone.

iOS test targets may install test-only documents/scripts and construct controlled frames/origin conditions. They must use actual WKWebView security-origin/main-frame metadata, not a Boolean hardcoded true. The production page CSP blocks frames; a dedicated test fixture/document with controlled test CSP is permitted to exercise the adapter's same-origin iframe denial separately. Test-only documents/fixture URLs stay out of native production sources and cannot widen the production app policies. Test probes must not become an enabled native debug endpoint or an arbitrary JS evaluation backdoor in the delivered app. Record whether each result came from unit doubles or actual WebKit.

For redirect denial, record zero hit count at destination, not just the returned error. For cancellation/deadline, observe URLSession cancellation plus server connection close or an appropriate native network delegate trace; HTTP error rendering alone cannot prove work termination. For document lifetime, submit slow work, reload, submit a new id, then wait past old completion and assert no stale UI/result contamination.

## Durable exact-RC evidence format

Each handoff names head_sha, branch, workspace, changed paths, tests/commands/exit codes and limits. Essential results belong in committed text under that module's scope or card metadata/comments, not solely .artifacts paths that disappear with worktree cleanup. Keep raw logs/screenshots/xcresult in ignored .artifacts during execution; preserve a small sanitized transcript/extract or native task attachment if it is needed downstream. Do not copy secrets or raw unrelated environment state.

Integration/acceptance evidence must contain:

1. Exact merged reviewed parent heads and tested RC head; tool versions and Simulator runtime/UDID.
2. Every gate with passed/failed/skipped totals, actual command and exit code, test names covering the matrix, and any material failure disposition.
3. A/B web file hashes, installed executable SHA-256 and full installed .app file-manifest digest before/after, installed path and no-rebuild/no-reinstall transcript between observations.
4. A/B visible UI assertions plus matching backend method/path/tag logs and native execution evidence; screenshots optional, not substituted for assertions.
5. Real provenance/iframe/redirect/revocation/timeout/cancel/concurrency/size observations and source audit showing native production has no business endpoint registry/models.
6. Start/stop/owned process identities, delay cancellation observations, final listener checks and foreign-listener preservation; owned Simulator session shutdown.
7. Explicit limits: Simulator only, synthetic local HTTP, no credentials, no production security claim, any OS buffering limitation and unmeasured property.

## Gates and stop conditions

Foundation self-validation → independent same-card spec review → module implementation with RED/GREEN evidence and same-card review → exact integrated RC review → fresh independent real acceptance → coordinator reconciliation/owner RC decision. Do not create parallel replacement graphs, self-approve implementation, publish or archive early. Missing product intent blocks for coordinator; normal technical choices are already pinned here. Two same-root review cycles require technical replanning, not endless patching. A failed required behavior leaves acceptance incomplete even when the OpenSpec validator is green.
