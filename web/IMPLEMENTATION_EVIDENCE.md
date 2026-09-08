# Web implementation evidence — PER-85

Candidate scope: `web/` only, based on independently approved foundation `e9f338142735b754362c59ed62ad1fa8450c0b4e`. The checked-in `web/dist` is variant B. This record is module evidence, not real WKWebView or final product acceptance.

## Exact local gates

All commands ran from the assigned worktree on Node `v26.5.0` and npm `11.17.0`; commands wrapped in `cd web` ran from the scoped module directory.

| Command | Result |
| --- | --- |
| `(cd web && npm ci --no-audit --no-fund --cache ../.artifacts/npm-cache)` | exit 0; 193 packages installed from lockfile |
| `(cd web && npm audit --audit-level=high)` | exit 0; full production and development tree, 0 vulnerabilities |
| `npm --prefix web test -- --run --reporter=dot` | exit 0; 3 files, 23 tests passed |
| `npm --prefix web run typecheck` | exit 0 |
| `npm --prefix web run build:a` twice | both exit 0; byte-identical external JS/CSS production assets |
| `npm --prefix web run build:b` twice | both exit 0; byte-identical external JS/CSS production assets; final `web/dist` |
| `node protocol/v1/validate.cjs` | exit 0; 36 schema/example classifications passed |
| `OPENSPEC_TELEMETRY=0 OPENSPEC_NO_COMPLETIONS=1 openspec/tooling/node_modules/.bin/openspec validate --all --strict --no-interactive --json` | exit 0; `add-bridge-lab` valid |
| `git diff --check` | exit 0 |

The reviewer-found Vite/Vitest advisories were resolved with exact pins `vite@7.3.6`, `@vitejs/plugin-react@5.2.0`, and `vitest@3.2.6`; the regenerated lockfile resolves `esbuild@0.28.2`. Full `npm audit --audit-level=high` reports zero vulnerabilities. The local npm policy still warns that install scripts for `esbuild@0.28.2` and optional `fsevents@2.3.3` are not pre-approved; clean install and all builds completed without changing global/profile policy. `npm ci` also prints the upstream `whatwg-encoding@3.1.1` deprecation warning.

## Deterministic web-only variants

Exact round-2 pre-commit build hashes; each variant produced the same manifest on two consecutive clean-output builds:

- Variant A: JS `ef1217afc1a6326f5aadd1a3855a166eaa1742fdab742c76f5c9cca0565d8f83`; CSS `a30a77bb4e9fd5ecba1aba59f1d5c63488938cfa1c9530d5bd2064925273d6b2`; index `3df85175d29bb3639ec9e2f403434cfbd7f21bde14e7aca94012b257a101c6b9`.
- Variant B: JS `97b3a2c8fdc080e725834e1a1c17b12ddb6623049bcf4efc8aa6eaa7e1d66d85`; CSS `a30a77bb4e9fd5ecba1aba59f1d5c63488938cfa1c9530d5bd2064925273d6b2`; index `5886f28090351f475934727d94b895c7da3f5cc3e80dbaa86aea63447217d86f`.

A and B manifests differ. Built HTML has an external module script and stylesheet, no inline script/style. The built JavaScript contains no `fetch(` call; Vite's module-preload fetch polyfill is disabled. Production source contains no fetch/XHR fallback or test mock import.

## Requirement coverage

- WS-01: catalog GET owns category query and list parsing; quote POST owns JSON body and nested quote parsing. Variant A defaults to catalog and variant B to quote while both expose the selector.
- WS-02: tests cover loading/result, HTTP, business, JSON parse, native transport timeout/cancel, missing bridge, malformed/mismatched reply, concurrent out-of-order correlation and cancel isolation. Reply parsing now fail-closes above the inclusive 1,048,576-byte UTF-8 response-body bound; tests cover exact ASCII acceptance, one-byte ASCII excess, and a multibyte excess whose JavaScript character length alone would fit. Test native boundaries are explicitly named mocks and are absent from production imports.
- WS-03 module input: `build:a` and `build:b` replace the same `web/dist` with differing assets and behavior. Same installed iOS binary proof is intentionally deferred to integration/acceptance.
- WB-03/04 web portions: one hello/session per document client, monotonic ids, correlated request/cancel promises, closed reply validation, and best-effort pagehide cancellation. Native revocation remains authoritative.

## Known limits and downstream inputs

Real WKWebView, URLSession, backend, fixed-port lifecycle, CSP response headers, Simulator A/B interaction, and installed app/bundle hash equality were not exercised by this web-only card. Integration must merge this card's independently reviewed exact head, run `npm ci --prefix web`, use `npm --prefix web run build:a` then `build:b`, and verify the actual WKWebView/native/backend path plus unchanged installed executable and bundle hashes. Variant B is the committed default `web/dist`; integration may deterministically rebuild either variant without changing iOS sources.
