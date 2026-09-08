# Backend implementation evidence — t_7ecc568f

Candidate only; independent same-card review and later Simulator acceptance remain required. Approved foundation e9f338142735b754362c59ed62ad1fa8450c0b4e is preserved as an ancestor through merge 0dd42313f93a2a7a31223cc2b7ba44003b63c071. Exact candidate head is recorded in the Kanban review handoff.

## Executed gates

Environment observed: macOS, Node v26.5.0; dependency-free Node built-ins. `scripts/lab` uses `/bin/ps` for process start/command identity. Other operating systems/Node versions were not exercised.

- `node --check backend/server.mjs`: exit 0.
- `node --check scripts/lab`: exit 0.
- `node --test --test-reporter=tap backend/tests/*.test.mjs`: exit 0, 41 tests passed, 0 failed/cancelled/skipped/todo. Full actual stdout retained in [verification.tap](verification.tap).
- `git diff --cached --check`: exit 0.
- Post-test process inspection filtered the exact own-worktree server script: no remaining server PIDs. Lifecycle tests additionally assert owned PID exit, actual rebind of both released ports, delayed-connection closure, and continued foreign-listener health.

The tests execute the real executable CLI in subprocesses from another cwd, not a mocked lifecycle. CLI-started server is the single tracked child owning both listeners; it spawns no grandchildren. Tests use ephemeral ports; state/assets are under ignored `.artifacts/backend-tests/` and removed in cleanup. The lifecycle harness retries confirmed `listen/EADDRINUSE` failures at most three times, recreating isolated roots and ports after cleanup. CLI preflight occupied-port diagnostics or a failed-start log containing the actual bind error identify collisions; assertion, ownership, configuration and unrelated startup errors are not retried. Concurrent commands settle before cleanup. The intentional foreign-port refusal test still uses the raw CLI and requires failure. Argument-validation tests keep ephemeral reservations open throughout, eliminating their release-to-bind race and proving validation precedes listening.

## Requirement mapping

| Requirement | Executable evidence |
| --- | --- |
| LL-01 deterministic fixtures | fixtures.test.mjs: catalog GET, quote POST/nested response/validation, opaque echo, HTTP 503, malformed JSON, business error, wrong method/unknown path, request-body cap |
| LL-01 delayed/security inputs | fixtures.test.mjs: bounded delay and client abort/connection-close, same/cross/loop redirect, chunked large payload, invalid UTF-8, binary, synthetic header/cookie inputs, no CORS |
| LL-01 current web assets | fixtures.test.mjs: missing-root 503 vs health, live file replacement, MIME/CSP/no-store, traversal and symlink escape denial |
| LL-02 owned lifecycle | lifecycle.test.mjs: real start/status/stop, idempotency, concurrent invocations, foreign conflict, stale/PID-reuse state, partial second-bind rollback, active-work shutdown and released listeners/child PID |
| LL-02 ownership validation | arguments.test.mjs and lifecycle.test.mjs: invalid ports/root/token/options; live PID plus wrong command/start identity, shortened/empty token refusal, stale lock/malformed state recovery, configuration mismatch preserves live service |
| LL-01/LL-02 static resource closure | static-cleanup.test.mjs: real 16 MiB full downloads and actual source-descriptor counts via macOS lsof; five client aborts and server close during a paused response leave zero descriptors |
| LL-02 isolated bind retry | port-retry.test.mjs and lifecycle.test.mjs: forced real listener collision, fresh-port recovery, fresh CLI state roots, three-attempt exhaustion, no assertion/ownership retries, foreign listener preserved, successful retry child exit and both ports released |
| LL-03 handoff | This document, committed actual TAP, exact-head review metadata. Simulator/WebKit and integrated same-binary acceptance belong to downstream cards and are not claimed here. |

## Recovery and RED/GREEN history

The prior timed-out attempt left uncommitted source/tests with a malformed parser expression. Recovery preserved those files. Initial full suite failed before loading either test module with SyntaxError at server.mjs:507. Minimal syntax repair then allowed targeted argument tests to demonstrate negative/out-of-range ports reaching Node's bind validation and missing/foreign repository bindings incorrectly starting the server. Added explicit bounds and exact repository binding; all original plus parser tests passed (33).

A further ownership regression test failed because a shortened token passed substring-based process verification (status exit 0 instead of 1). Fixed token shape and full expected command equality while retaining start identity checks. Added real child-exit, stale-recovery, configuration-mismatch and live-PID/command negatives. Final suite passed all 35 tests. One TAP tee attempt ran tests successfully but failed its output-path creation (exit 1); the recorded final gate was rerun successfully to the committed evidence file. Original pre-recovery TDD ordering is not independently reconstructable here; these recovery defects were reproduced before their behavior fixes.

## Downstream use and limits

### Review round 1 rework

Reviewer R1 reproduced before the fix: `node --test backend/tests/static-cleanup.test.mjs` exited 1 with 5 open source descriptors after five client aborts and 1 after active server shutdown (expected 0); ordinary full downloads closed their sources. The fix destroys static sources on response close/error, avoids opening a source after asynchronous path checks if the response already closed, and makes server shutdown await pending web handlers through actual source close. Both regressions and existing fixture tests then passed (13/13). The regression uses real HTTP and `/usr/sbin/lsof`, not a mocked stream; macOS tooling is required.

Reviewer R2 reproduced before the retry implementation: `node --test backend/tests/port-retry.test.mjs` exited 1 (2 failed, 1 passed): the forced collision escaped on the first attempt and exhaustion lacked a bounded diagnostic. The bounded test-only helper and CLI harness now recover with fresh resources. Real CLI forced-collision recovery and exhaustion are also exercised; `scripts/lab` itself remains unchanged. Final full suite: 41/41 PASS. No specification was weakened. These fixes are candidates for independent round 2, not self-approved acceptance.

Merge the independently approved exact candidate commit, not an unreviewed working directory. Run `node --test backend/tests/*.test.mjs` from the repo; no package install is needed. Use `scripts/lab start|status|stop` with identical options throughout a session; see [README](README.md). Defaults serve `web/dist` on loopback 8787 and fixture API on 8788. Web builds/replaces its own assets; backend never embeds or builds React. Keep the same Node executable available between start and stop because it is part of verified process identity. Always stop before moving/deleting a worktree.

Ownership checks defend against stale/reused PIDs and mismatched state, not a malicious same-user process deliberately forging its process arguments or modifying the private local state. This is a controlled synthetic local lab, not an authenticated multiuser service or production server. No real secrets/auth/data, remote services, daemon registration, native/web/iOS changes, main merge, or publication were involved. Native timeout/cancel/redirect rejection, bridge origin security, actual React build and unchanged installed Simulator binary must still be verified by integration and independent acceptance.
