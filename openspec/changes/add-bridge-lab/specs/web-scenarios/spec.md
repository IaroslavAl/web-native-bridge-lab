## Purpose

Web-owned request construction and domain interpretation demonstrated across two served builds on one installed iOS app.

## ADDED Requirements

### Requirement: WS-01 Two web-owned scenarios

React SHALL implement catalog GET and quote POST with distinct endpoints and JSON shapes, constructing full URL/query/allowed headers/body in web and parsing results only in web per docs/architecture.md.

#### Scenario: Catalog A
- **WHEN** the user submits catalog with category books
- **THEN** web renders Notebook from items and total 1 after native HTTP execution

#### Scenario: Quote B
- **WHEN** the user submits notebook quantity 2
- **THEN** web renders USD totalMinor 1200 from nested quote after native HTTP execution

### Requirement: WS-02 Honest error and request UX

Web SHALL distinguish loading, result, HTTP failure, business error, JSON parse failure, transport timeout/cancel/error and unavailable bridge; it SHALL NOT silently fall back to browser fetch.

#### Scenario: Error categories
- **WHEN** HTTP error, business-error or malformed-json fixtures are selected
- **THEN** web labels the corresponding category instead of treating all three as network failure

#### Scenario: Missing bridge
- **WHEN** the page runs in a plain browser without nativeHTTP
- **THEN** it displays bridge unavailable and issues no substitute API fetch

#### Scenario: Concurrent cancel UI
- **WHEN** fast and slow requests run concurrently and the slow one is cancelled
- **THEN** fast result stays correctly associated, slow request shows cancellation and loading settles

### Requirement: WS-03 Same installed binary web update

The lab SHALL demonstrate build:a to build:b web replacement with changed default endpoint/JSON rendering on the same installed Simulator executable and bundle, using the proof procedure in docs/architecture.md.

#### Scenario: Web-only update
- **WHEN** A catalog succeeds, only served web assets are rebuilt to B, and the user reloads
- **THEN** B quote succeeds with changed web hashes and identical before/after installed executable and bundle hashes, without iOS rebuild or reinstall
