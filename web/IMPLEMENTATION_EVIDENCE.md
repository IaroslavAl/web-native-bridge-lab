# Web implementation evidence — PER-85

Candidate scope: `web/` only, based on independently approved foundation `e9f338142735b754362c59ed62ad1fa8450c0b4e`. The checked-in `web/dist` is variant B. This record is module evidence, not real WKWebView or final product acceptance.

## Exact local gates

All commands ran from the assigned worktree on Node `v26.5.0` and npm `11.17.0`.

| Command | Result |
| --- | --- |
| `npm ci --prefix web --no-audit --no-fund --cache "$PWD/.artifacts/npm-cache"` | exit 0; 185 packages installed from lockfile |
| `npm --prefix web test -- --run` | exit 0; 3 files, 20 tests passed |
| `npm --prefix web run typecheck` | exit 0 |
| `npm --prefix web run build:a` | exit 0; external JS/CSS production assets |
| `npm --prefix web run build:b` | exit 0; external JS/CSS production assets; final `web/dist` |
| `(cd web && npm audit --omit=dev --audit-level=high)` | exit 0; 0 vulnerabilities |
| `node protocol/v1/validate.cjs` | exit 0; 36 schema/example classifications passed |
| `OPENSPEC_TELEMETRY=0 OPENSPEC_NO_COMPLETIONS=1 openspec/tooling/node_modules/.bin/openspec validate --all --strict --no-interactive --json` | exit 0; `add-bridge-lab` valid |
| `git diff --check` | exit 0 |

The local npm policy emitted a warning that install scripts for `esbuild@0.21.5` and optional `fsevents@2.3.3` were not pre-approved; installation and both Vite builds nevertheless completed successfully without changing global/profile policy.

## Deterministic web-only variants

Exact final pre-commit build hashes:

- Variant A: JS `fbf20b99233984998d9edca8997dec6b25932197c8e05b6d1944ac1fff2d3e2a`; CSS `e884af892d316d7f539507ac39fc254e01e79672e8dbee855a7c0be63760e067`; index `05f6d64a66cec6385440dcc4e54279575b1d6cf908bc53480709a917651d1e21`.
- Variant B: JS `15482a0a07d86bf72ff90dbc46a521d373ff63db6cb8d6c8e4ae5e741295960f`; CSS `e884af892d316d7f539507ac39fc254e01e79672e8dbee855a7c0be63760e067`; index `9304f3c856c2b8e6ea25780fee354998cc5d903a33a3426e27775347b5d1d419`.

A and B manifests differ. Built HTML has an external module script and stylesheet, no inline script/style. The built JavaScript contains no `fetch(` call; Vite's module-preload fetch polyfill is disabled. Production source contains no fetch/XHR fallback or test mock import.

## Requirement coverage

- WS-01: catalog GET owns category query and list parsing; quote POST owns JSON body and nested quote parsing. Variant A defaults to catalog and variant B to quote while both expose the selector.
- WS-02: tests cover loading/result, HTTP, business, JSON parse, native transport timeout/cancel, missing bridge, malformed/mismatched reply, concurrent out-of-order correlation and cancel isolation. Test native boundaries are explicitly named mocks and are absent from production imports.
- WS-03 module input: `build:a` and `build:b` replace the same `web/dist` with differing assets and behavior. Same installed iOS binary proof is intentionally deferred to integration/acceptance.
- WB-03/04 web portions: one hello/session per document client, monotonic ids, correlated request/cancel promises, closed reply validation, and best-effort pagehide cancellation. Native revocation remains authoritative.

## Known limits and downstream inputs

Real WKWebView, URLSession, backend, fixed-port lifecycle, CSP response headers, Simulator A/B interaction, and installed app/bundle hash equality were not exercised by this web-only card. Integration must merge this card's independently reviewed exact head, run `npm ci --prefix web`, use `npm --prefix web run build:a` then `build:b`, and verify the actual WKWebView/native/backend path plus unchanged installed executable and bundle hashes. Variant B is the committed default `web/dist`; integration may deterministically rebuild either variant without changing iOS sources.
