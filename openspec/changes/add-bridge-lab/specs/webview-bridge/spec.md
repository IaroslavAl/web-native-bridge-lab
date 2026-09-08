## Purpose

A versioned WebKit boundary that grants generic HTTP only to the trusted active main document.

## ADDED Requirements

### Requirement: WB-01 Versioned closed envelopes

The adapter SHALL accept and return only the v1 shapes and ordered validation behavior in protocol/v1/README.md and schema.json.

#### Scenario: Unsupported version
- **WHEN** a trusted message has version 2, a string version or no version
- **THEN** a v1 UNSUPPORTED_VERSION error is returned without network work

#### Scenario: Malformed input
- **WHEN** a non-string, invalid JSON, unknown field, invalid id or oversize message is sent
- **THEN** the specified INVALID_REQUEST or MESSAGE_TOO_LARGE result is returned, with null id when unrecoverable

### Requirement: WB-02 Separate trusted document authority

The adapter SHALL enforce trusted origin, committed active generation and main-frame checks independently of the request API allowlist.

#### Scenario: Origin and iframe denial
- **WHEN** an untrusted origin, same-origin iframe, pre-commit or inactive document attempts a bridge call
- **THEN** ORIGIN_DENIED is returned to that invocation only and no API work starts

#### Scenario: No external navigation
- **WHEN** the page tries to navigate the main frame to a foreign origin or create a new window
- **THEN** navigation is denied and no external application is opened

### Requirement: WB-03 Correlation and safe replies

The adapter SHALL implement monotonically increasing per-document ids, structured WebKit replies and independent request/cancel Promises as defined in protocol/v1/README.md.

#### Scenario: Duplicate request
- **WHEN** an active or previously consumed id is submitted again
- **THEN** the new invocation fails INVALID_REQUEST without replacing or settling the original request

#### Scenario: Document handshake and stale token
- **WHEN** a trusted document repeats hello, or an old queued request echoes a token revoked by same-URL reload
- **THEN** repeated hello returns the same live session without resetting ids, while the stale request receives ORIGIN_DENIED without work or new-document delivery

#### Scenario: Safe text delivery
- **WHEN** a response body includes quotes, closing script tags, backslashes and Unicode
- **THEN** the exact text reaches its request Promise without executing that text

#### Scenario: Cancel acknowledgement
- **WHEN** a cancel targets active, completed or unknown id
- **THEN** only active cancellation that wins returns cancelled true; the original active request receives CANCELLED

### Requirement: WB-04 Document revocation

The adapter SHALL revoke and cancel prior generation work on allowed navigation, reload, close, provisional failure, web-process termination and teardown, and SHALL NOT deliver old results into a new document.

#### Scenario: Reload id reuse
- **WHEN** a delayed request is active when the page reloads and the new page uses id 1
- **THEN** old task is cancelled/retired and its late reply cannot affect the new request

#### Scenario: Teardown
- **WHEN** the WebView closes or its content process terminates with active work
- **THEN** underlying tasks/deadlines are cancelled and reply handles and handler ownership are released
