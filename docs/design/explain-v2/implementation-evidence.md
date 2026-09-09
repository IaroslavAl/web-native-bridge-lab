# Explain v2 web implementation evidence

Candidate phase: W only. This record does not claim native N, integrated runtime R, final acceptance A, or owner RC readiness.

## Implemented scope

- The production demo is a compact Russian Screen → Application → Server journey with one current action, adjacent live status/result/error, and no engineering controls in the main flow.
- A exposes only the real catalog request. B exposes only the real notebook quantity-2 quote request. Structured response values remain web-owned; returned catalog identity and validated quote quantity/minor units/currency drive the visible result.
- Pending and result copy follows BridgeClient Promise events without fake acknowledgement, server progress, publication state, timers, fetch fallback, or minimum animation duration. Reload pending preserves its own action and cannot show business-request waiting or success copy. Main journey and A→B comparison copy use plain Russian while technical detail stays in the engineering surface.
- Duplicate activation is excluded synchronously. Detached/reloaded documents cannot repaint from stale completions. A failed handshake retry creates a fresh production BridgeClient instead of reusing its cached rejected session Promise.
- Loaded identity is the compiled variant plus the emitted `import.meta.url` asset path. The bounded, closed `per85.explain.v1` session record is continuity only, consumed once after a bridge startup attempt, and never grants B capability.
- The participant update action writes valid continuity when possible and calls same-origin `window.location.reload()`. Same A, changed A, observed A→B, cold B, and unavailable/corrupt storage are distinguished without binary-integrity or presenter-publication claims.
- The old production engineering controls and technical summaries moved to exact opt-in diagnostics mode. Diagnostics clears only the continuity key and does not consume demo history. Hostile response text remains inert; fast-result/slow-only-cancel coverage is retained.
- `index.html` has a static Russian pre-React failure explanation. CSS keeps route/status/action in a bright responsive flow, uses semantic status/alert content and 48px actions, and disables motion under `prefers-reduced-motion`.
- README marks the native footer long-press/VoiceOver diagnostics entry as pending N and explicitly says a browser query URL has no native bridge.

## Executed gates

All commands ran from exact source branch `web-native-bridge-lab/t_72d67948-per-85-explain-v2-web-implementer`, based on reviewed parent `b50e3469df4f7c214f5a0cc1ce277e4a8512845b`.

- `npm --prefix web test -- --run` — PASS: 6 files, 54 tests.
- `npm --prefix web run typecheck` — PASS.
- `npm --prefix web run build:a -- --outDir ../.artifacts/explain-web-a` — PASS; emitted `/assets/index-B02rsMN0.js`.
- `npm --prefix web run build:b -- --outDir ../.artifacts/explain-web-b` — PASS; emitted `/assets/index-BQCeerPS.js`.
- `node protocol/v1/validate.cjs` — PASS: 36 vectors (14 valid, 15 invalid, 7 semantic-only classifications; semantic-only codes are not runtime proof).
- `OPENSPEC_TELEMETRY=0 openspec/tooling/node_modules/.bin/openspec validate --all --strict --no-interactive` — PASS: 2 changes, 0 failures.
- `git diff --check` — PASS.

## Built identity evidence

The final isolated A/B outputs have distinct emitted entry paths and bytes:

- A SHA-256: `647633da29c7ce1b8518b1e9928e42030d9834d0b31c96a662aac10d49dc15ff`
- B SHA-256: `4709a62a193c3ae47336a5d8cc09eb4645f31caa893048e7c86cc830a1152cf5`

Readback confirmed each built HTML references its corresponding content-hashed entry and retains the static Russian bootstrap fallback. Search of each compiled entry confirmed its own compiled variant is paired with `import.meta.url`, and that continuity, diagnostics selection, catalog copy, and quote copy are present. `cmp` confirmed the entries differ. Production `web/src` contains no `fetch(`, `innerHTML`, or `dangerouslySetInnerHTML` use.

## Deliberate limitations / pending gates

- Unit UI evidence uses explicitly labelled native doubles. No backend, WKWebView, Simulator, service, native build, installed footer interaction, screenshot, safe-area/Dynamic Type measurement, or same-installed-app proof ran in W.
- Existing native SameBinaryTests still expect the old visible controls and labels. N owns the native footer entry, native version/build label, generic load recovery, and shared UI-harness alignment before Stage5 can pass on Explain v2.
- R owns real served A→B/update/failure/layout evidence. A remains the independent exact-candidate acceptance gate. The active OpenSpec change is not archived here.
- No protocol, bridge client, native, backend, runner, tracked dist, profile, remote, or original mission-graph changes were made.
