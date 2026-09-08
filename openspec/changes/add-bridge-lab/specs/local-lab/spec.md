## Purpose

Opt-in loopback fixtures and reproducible evidence with verified resource ownership and clean shutdown.

## ADDED Requirements

### Requirement: LL-01 Deterministic local fixtures

Backend SHALL serve current built assets and every synthetic route, status, body, delay and security fixture specified in docs/architecture.md using only the fixed loopback listeners by default.

#### Scenario: Static web replacement
- **WHEN** web/dist is rebuilt or absent
- **THEN** new completed assets are served without caching, or absence returns explicit 503 rather than a fake demo

#### Scenario: Fixture coverage
- **WHEN** the fixture contract table is exercised including invalid input, redirect, size and header routes
- **THEN** all specified statuses, bodies, content types and bounded delays match and no real data/auth is used

#### Scenario: Safe asset path
- **WHEN** a request attempts traversal or a symlink escape from web/dist
- **THEN** no outside file is served

### Requirement: LL-02 Owned opt-in lifecycle

scripts/lab SHALL provide the start/status/stop interface, readiness deadlines, state locking, ownership checks and cleanup semantics in docs/architecture.md with no autostart or permanent daemon.

#### Scenario: Repeat and conflict
- **WHEN** start/stop repeat or start encounters a foreign occupied port
- **THEN** healthy owned start and stopped stop are idempotent; conflict fails without signalling the foreign process

#### Scenario: Stale or partial startup
- **WHEN** state refers to a reused PID or the second listener cannot start
- **THEN** ownership mismatch is never killed and any newly started owned listener is cleaned up

#### Scenario: Shutdown active work
- **WHEN** stop runs with delayed requests and owned children
- **THEN** own sockets/timers/children close, ports are verified released and unrelated listeners remain alive

### Requirement: LL-03 Reproducible independent acceptance

The project SHALL retain command-backed exact-head verification per docs/verification-plan.md, including actual Simulator WebKit end-to-end behavior, independent review and explicit limits, before claiming accepted completion.

#### Scenario: Real acceptance
- **WHEN** integration and a fresh verifier exercise the RC
- **THEN** evidence identifies exact commits, installed hashes, real UI/backend observations, tests passed/failed/skipped and cleanup; mocks alone cannot pass

#### Scenario: Lifecycle closure
- **WHEN** implementation exists but a required test or review is missing
- **THEN** the corresponding task remains incomplete and the active change is not archived as accepted
