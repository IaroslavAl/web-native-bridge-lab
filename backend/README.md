# Local fixture backend

This module is the synthetic, credential-free backend for the Simulator-only Web–Native Bridge Lab. It uses Node built-ins and binds only `127.0.0.1`.

## Lifecycle

Use the single repository entry point from any working directory:

    /absolute/path/to/repo/scripts/lab start
    /absolute/path/to/repo/scripts/lab status
    /absolute/path/to/repo/scripts/lab stop

Defaults:

- web listener: `http://127.0.0.1:8787`, serving the current `web/dist` from disk;
- API listener: `http://127.0.0.1:8788`;
- state and logs: `<repo>/.artifacts/lab/` (ignored by Git).

All commands accept the same overrides for isolated tests:

    scripts/lab <command> \
      --state-dir /absolute/state/path \
      --web-port 49151 \
      --api-port 49152 \
      --web-root /absolute/web/dist

Ports must be distinct integers from 1 through 65535. Overrides do not alter the production iOS allowlist. `start` is opt-in and returns only after both health routes respond. Repeating a healthy start is safe. `status` prints one JSON object and exits 0 only for verified `running`; `stopped`, `stale`, and `conflict` exit 1. `stop` verifies PID start identity, canonical server path, ownership token, repository root, state directory, and requested configuration before sending a signal. It never kills an unverified or foreign process.

`assetsAvailable` reports whether a real in-root `index.html` currently exists. The web listener remains healthy when assets are absent; asset requests then return 503. Rebuilding or atomically replacing `web/dist` requires no backend restart.

The lifecycle creates no daemon registration or autostart. Always run `scripts/lab stop` after a manual session. Request and lifecycle logs never include bodies, query values, credentials, or environment data.

## Fixture routes

Both listeners expose `GET /healthz`. API behavior is defined by `docs/architecture.md` and implemented here:

- `GET /api/catalog?category=books`
- `POST /api/quote`
- `POST /fixtures/echo`
- `GET /fixtures/http-error`
- `GET /fixtures/malformed-json`
- `GET /fixtures/business-error`
- `GET /fixtures/delay?ms=<0..30000>&label=<printable ASCII>`
- `GET /fixtures/redirect-same`
- `GET /fixtures/redirect-cross`
- `GET /fixtures/redirect-loop`
- `GET /fixtures/large?bytes=<0..1048577>`
- `GET /fixtures/invalid-utf8`
- `GET /fixtures/binary`
- `GET /fixtures/headers`

All responses disable caching. API responses grant no CORS permission and use no authentication. Static paths are resolved under the current real web root, with traversal, directory listing, and symlink escape denied. The web listener applies the foundation CSP to success and error responses.

## Tests

Run isolated real-listener and process-lifecycle tests:

    node --test backend/tests/*.test.mjs

Tests allocate temporary loopback ports and state roots. They cover fixture contracts, current asset replacement, traversal/symlink denial, body and delay bounds, client-close cleanup, redirect inputs, stale/PID-reuse defense, concurrent lifecycle calls, partial-start rollback, released owned ports, and preservation of unrelated listeners.
