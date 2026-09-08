# Integration Stage 1 — coordinator checkpoint (not final acceptance)

Task `t_9d8fd391`, board `web-native-bridge-lab`, declared project `p_ce173eae`.
Branch `web-native-bridge-lab/t_9d8fd391-per-85-integration-implementer`.
Workspace `/Users/agent/hermes-clean-20260903/projects/web-native-bridge-lab/.worktrees/t_9d8fd391`. Git common-dir is the primary repository `.git`; primary main was not modified. Model/provider were explicitly routed by coordinator to Astra / openai-codex / high (card override and session context; effort from release packet, not independently process-measured). No runtime/profile changes, child agents, new cards or publication.

## Inputs and scoped changes

Merged exact independently approved parent heads, no conflicts or cherry-picks:
- iOS/native lifecycle: `15a9b53698357fc9e4a828f045e079d9644710de`.
- Web: `6936e00938b92c617e975784b5b776dd95247870`.
- Backend: `4e4474f1e39dda7ad6e0f421eee9dc49583b0229`.
- Transitive foundation `e9f338142735b754362c59ed62ad1fa8450c0b4e` and transport `b5c5423c585b8599f5639075e5c40c8a5f517ada` verified as ancestors; newer iOS transport changes preserved.

Added `scripts/verify`, its evidence-helper tests, top-level reproduction instructions, a separate `BridgeLabAcceptance` scheme and `BridgeLabUITests` target/test, and this evidence. Production Swift, React, backend, wire semantics and policies are unchanged. The checkpoint commit containing this document is the exact downstream input; the handoff records its SHA. `stage1-evidence.json/source.json` records the pre-checkpoint merge HEAD plus working diff during execution, not a claim that uncommitted changes were already in that HEAD.

## Real execution

Xcode 26.6 (17F113), iOS 26.5 arm64 / iPhone 17 Pro, Node v26.5.0, npm 11.17.0, Apple Python 3.9.

- `scripts/verify unit`: PASS. Evidence-helper tests 3; backend HTTP/process tests 41; native package 39; iOS package 19; React tests 23. All passed. Swift uses warnings-as-errors. TypeScript, schema (14 valid + 15 invalid + 7 semantic-only classifications), strict OpenSpec and A/B builds PASS. Full web dependency audit: 0 vulnerabilities. Schema classifications are not runtime semantics.
- `scripts/verify simulator-stage1`: PASS. Existing actual Simulator suite 42 passed, 0 failed/skipped; actual XCTest UI A/B test 1 passed, 0 failed/skipped. Result bundles independently parsed by `xcresulttool`; no unit/native boundary mock in the A/B path.
- `plutil -lint` project, XML scheme validation, Python parse and `git diff --check`: PASS.
- Initial evidence helpers had two expected assertion failures before implementation (missing manifest/equality helpers), then GREEN. Hidden-file/symlink check was added as regression coverage and passed first run, not claimed RED. New UI tests verify existing integrated behavior; no production feature RED/GREEN claim.

Core logs: `.artifacts/verify-unit-9b9213adaf`. Final Simulator logs: `.artifacts/verify-simulator-stage1-7f955bba81`. These paths are disposable. Exact commands, exit codes, complete installed manifests, results, selected lifecycle/network records and raw-log hashes are retained in committed `stage1-evidence.json`. Screenshots remain optional attachments inside ignored `ab.xcresult` and are not the only proof.

## Same installed production application

Device: `590F6FAA-46F4-408D-92D8-3939F5EF245C` (deleted after evidence capture).
Installed container before A, after A and after B:
`/Users/agent/Library/Developer/CoreSimulator/Devices/590F6FAA-46F4-408D-92D8-3939F5EF245C/data/Containers/Bundle/Application/10FF0945-F66B-4181-9C27-69ADAFA0C06F/BridgeLab.app`.

- Complete installed file count: 3; full file maps equal across all three observations, no exclusions, no unit-test bundles or XCTest artifacts.
- Executable SHA256: `cccde0b4d3f3c2520496b16921c4a228995e91752c6b2c59173deb20eb1845b9`.
- Manifest digest: `d5d8700154bbae12eb1ee5671e8382702c3fec3d53d72e0b7959940f97509a25` (SHA256 of UTF-8 `json.dumps(files, sort_keys=True)`; full map retained).
- A React UI: `Catalog default`, submit, actual `Notebook (notebook) — total 1` accessibility text.
- B: host rebuilds only served React assets, XCTest taps native `lab.reload`, sees `Quote default`, submits and reads actual `notebook × 2 — USD 1200 minor units`.
- Actual backend attribution: `GET /api/catalog 200 tag=scenario-a`, then `POST /api/quote 200 tag=scenario-b`.
- UI runner contacts only static `/stage1/*.txt` markers for synchronization, never API8788. App uses unchanged production bridge/executor, web has no fetch fallback, CSP connect-src is none. The test neither evaluates JS nor supplies synthetic result data to the app.
- Only web-build-B appears between A and B in the command ledger; native app is not rebuilt/reinstalled/relaunched and launch configuration does not change. Manifest equality includes container identity and UDID.

Web A JS: `ef1217afc1a6326f5aadd1a3855a166eaa1742fdab742c76f5c9cca0565d8f83`.
Web B JS: `97b3a2c8fdc080e725834e1a1c17b12ddb6623049bcf4efc8aa6eaa7e1d66d85`.
Full HTML/CSS/JS maps are retained in the evidence JSON and match independently reviewed module hashes.

## Harness finding and cleanup

First real run (`verify-simulator-stage1-f16c340652`) passed A/B but measured 42 files, including unit-test host artifacts because unit and acceptance builds shared derived data. A stricter assertion rejected that evidence for the final clean-shell claim. Second run (`verify-simulator-stage1-d058f580a0`) separated derived trees, but Simulator replacement installation retained the earlier unit-host PlugIns; the guard failed before A. Fresh acceptance build itself had only three files. Final runner additionally uninstalls its own unit host before installing the clean shell, strictly before A. Final run passed the guard and both UI scenarios; no clean-up edits inside an installed bundle or weakened assertion. Earlier failures are harness/install hygiene, not production bridge failures; all owned resources from all runs were cleaned.

Final `scripts/lab stop` exit0, stopped status exit1 (expected), both8787/8788 rebound successfully. Owned Simulator shutdown/delete exit0 and fresh simctl JSON confirmed absence. `cleanup.json` has no errors. No permanent service or foreign process signal. Existing backend41 tests cover foreign-listener preservation; the full integrated adverse-lifecycle/signal matrix is not claimed here. SIGINT/SIGTERM handlers and bounded cleanup exist; force-kill/host-crash recovery is not guaranteed. Only current worker-owned processes/devices were managed.

## Coverage and remaining gate

Stage1 provides HT-01/WS-01 happy-path GET/POST across real WKWebView/React/native/backend, WS-03 unchanged clean installed binary plus changed web behavior, core suites and normal LL-02 cleanup. Existing unit/component coverage is retained, not promoted to full end-to-end proof.

Still required in Stage2: real HTTP/JSON/business/transport error distinctions; timeout/cancel socket effects; concurrent correlation and bounds; real iframe/foreign-origin/navigation/redirect probes; populated synthetic credential stores; safe JS/data effects; adverse resource/signal isolation; complete requirement reconciliation. Independent same-card integration review and separate exact-RC acceptance/synthesis/owner RC are NOT done; no archive or main merge.

Reproduce with `scripts/verify unit` then `scripts/verify simulator-stage1` in the checkpoint tree. Coordinator must authorize Stage2 on this same card; no replacement graph. Stage1 requested scheduled hold. This worker exposes no schedule tool and its higher-priority protocol forbids shell board verbs, so the packet's CLI scheduling instruction cannot be executed here; coordinator owns that lifecycle hold.
