## Purpose

Generic credential-free native HTTP with bounded opaque text results, independent of business endpoints.

## ADDED Requirements

### Requirement: HT-01 Generic HTTP execution

The executor SHALL implement GET and POST as specified in protocol/v1/README.md and SHALL NOT define business endpoints or business JSON response types.

#### Scenario: Get query and post opaque body
- **WHEN** web submits catalog URL with an encoded category query or quote POST with JSON text
- **THEN** native preserves URL/query/header/body semantics, and returns status, allowed headers and opaque UTF-8 body without domain decoding

#### Scenario: Text body
- **WHEN** web submits POST text/plain to the echo fixture
- **THEN** native transports and returns the exact text

### Requirement: HT-02 HTTP outcomes remain distinct

The executor SHALL return non-redirect HTTP status responses, including 4xx/5xx, separately from native error envelopes, and SHALL leave JSON interpretation to web.

#### Scenario: HTTP failure
- **WHEN** the fixture returns 503 with JSON error body
- **THEN** response preserves status 503 and body rather than NETWORK_ERROR

#### Scenario: Malformed JSON
- **WHEN** the fixture returns 200 application/json with malformed JSON text
- **THEN** native returns that exact text successfully

#### Scenario: Connection failure
- **WHEN** the allowed API listener is absent
- **THEN** native returns NETWORK_ERROR without inventing an HTTP status

### Requirement: HT-03 Exact network policy

The executor SHALL enforce the exact API origin, URL grammar, header allowlist, GET/POST body rules and redirect denial in protocol/v1/README.md before prohibited work occurs.

#### Scenario: Denied target
- **WHEN** a request uses localhost, an alternate port, HTTPS, userinfo, a fragment, invalid escapes or a forbidden header
- **THEN** the defined validation code is returned and no prohibited network request starts

#### Scenario: Redirects
- **WHEN** the server returns a same-origin, cross-origin or looping redirect status
- **THEN** REDIRECT_DENIED is returned and no destination hop is requested

### Requirement: HT-04 No ambient credentials

The executor SHALL use credential/cookie/cache isolation and response header filtering as defined in protocol/v1/README.md.

#### Scenario: Cookie and header isolation
- **WHEN** shared cookie/credential stores are populated with synthetic test values and the fixture returns Set-Cookie and X-Private
- **THEN** no ambient credentials are sent or persisted by this session and neither header is exposed to web

#### Scenario: Authentication challenge
- **WHEN** an HTTP authentication challenge is received
- **THEN** the challenge is cancelled without credential lookup or user prompt

### Requirement: HT-05 Bounded execution

The executor SHALL enforce request/response/header byte limits, media type/UTF-8 rules, eight-live-request capacity and native monotonic deadlines from protocol/v1/README.md.

#### Scenario: Boundaries
- **WHEN** inputs or responses are exactly at each byte/time/concurrency limit and then exceed it by one
- **THEN** inclusive values are accepted where otherwise valid and excess gets the specified error without unbounded accumulation

#### Scenario: Chunked oversize
- **WHEN** the large fixture streams 1048577 decoded bytes without Content-Length
- **THEN** native cancels with RESPONSE_TOO_LARGE on crossing the cap

#### Scenario: Native deadline
- **WHEN** a request deadline expires while JavaScript is inactive or body chunks keep arriving
- **THEN** native ends underlying work with TIMEOUT, independent of JS or inactivity timeouts

#### Scenario: Unsupported response
- **WHEN** binary media or invalid UTF-8 is returned
- **THEN** native reports UNSUPPORTED_RESPONSE or RESPONSE_ENCODING respectively

### Requirement: HT-06 Exactly once terminal decision

The executor SHALL serialize cancellation, timeout and completion so the first terminal decision wins and underlying work is cancelled when required.

#### Scenario: Cancel wins
- **WHEN** an active delayed request is cancelled before its response
- **THEN** execute returns CANCELLED once, cancellation reports true, and late completion has no effect

#### Scenario: Response wins
- **WHEN** a response finishes before cancellation
- **THEN** the response remains the only result and cancellation reports false

#### Scenario: Concurrent responses
- **WHEN** a fast request completes before an earlier slow request
- **THEN** each id receives only its own result
