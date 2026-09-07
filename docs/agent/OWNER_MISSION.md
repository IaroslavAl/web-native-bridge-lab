# PER-85 — approved owner mission

Status: authorized by Yaroslav on 2026-09-07, Telegram 619532446:642724. PER-59 source hardening was independently accepted on 2026-09-07 (52 methods PASS; source e1ee6198091bd73a0547255c466466b9de73f27474961a72b19e832ae1e2ca76). A real project canary is still required before the full mission graph. Owner-facing explanations RU; specifications, tests and technical contracts EN. No further ordinary engineering approvals are required inside this scope.

## Outcome
Build a small but serious, maintainable standalone Web–Native Bridge Lab, intended for later experiments and eventual extraction as a production component. This first slice is NOT production-ready and is NOT a disposable spike. iOS presents WKWebView hosting remotely served React. React configures HTTP requests, iOS executes through a generic transport, then returns opaque response bodies; React parses JSON and interprets business success/errors. Native has no business endpoint registry or business response models.

Demonstrate two distinct web scenarios/endpoints/response shapes on the SAME installed iOS Simulator build, changing the served web payload without rebuilding/reinstalling iOS. This is a generic HTTP capability, not two hardcoded native fetch methods.

## Required first-slice behavior
- Versioned bridge request/response/error/cancel protocol with request correlation and predictable unsupported-version behavior.
- GET and POST with JSON/text body; URL assembled from host/path/query in web; allowed configurable headers. iOS transports body, never domain-decodes it.
- HTTP errors preserve status/body for web; distinguish transport errors, timeout, cancelled and invalid JSON handled by React.
- Timeout enforced by the actual network owner; cancellation terminates underlying work. Concurrent responses cannot cross requests.
- WebView navigation/close/reload revokes old document requests; no late result delivery into a new document.
- Distinct trusted web-origin policy and API allowlist, exact scheme/host/port checks, all redirect hops checked or redirects rejected. Native credentials/cookies not exposed; no authentication in this milestone.
- Bounded message/body sizes and concurrency chosen by delivery lead and captured in spec.
- Loopback local backend serves versioned/built React assets and deterministic demo API, error and controlled delay scenarios. Use synthetic data only.
- Documented start/status/stop lifecycle; no autostart or permanent daemon. Repeated start safe; refuse occupied foreign port; shutdown own children, close ports, no orphan processes, temp artifacts in predictable ignored paths.
- iOS Simulator only. Real device, signing provisioning or TestFlight are not required.
- Evidence must include real WKWebView -> native -> backend end to end, not just browser fetch mocks or native unit tests.

## Explicit non-goals
Full BDUI engine/home/widgets, deep links/native screen routing, Android, real credentials/auth, files/binary streaming, retry/cache platform, Railway/cloud deployment, App Store publication, work-project integration or confidential data. Long-term vision may be documented separately, not implemented in the first graph.

## OpenSpec and engineering
Use lightweight OpenSpec proposal/design/specs/tasks with requirement -> scenario -> test evidence; inspect official CLI docs and pin local project tooling (avoid changing global profiles/tools). Central contract with small iOS transport, bridge, TS client, demo UI and backend boundaries. Do not produce a monolithic universal platform or redundant documents. Product scope is already approved; coordinator/independent reviewer accepts technical design within that scope before implementation. Owner retains RC acceptance/publication; do not create a new owner gate for every engineering choice.

## Agent delivery acceptance
- One fresh real canary on canonical new project/board before full graph; verify worktree/cwd/common git dir and actual process model/effort.
- Graph creation through accepted atomic idempotent builder using literal PER-85 + phase + role; replay identical intent returns IDs, drift/duplicates fail closed. No raw repair scripts during pilot.
- Same-card independent review for each code implementation. Deliberate explicit same model/effort for implementer/reviewer is acceptable to avoid audited phase override race; use distinct worker sessions/roles. Do not claim reviewer metadata switches actual model. No mutation of other Hermes profiles without owner approval.
- Bounded independently verifiable cards planned20–40 iterations, max60; runtime/retry explicit, goal off. Escalate decomposition after two same-root review cycles.
- No stale actionable cards, no duplicate graph, no repairs, at most one owner-question after launch. If criteria fail, disclose rather than label clean.
- Low-noise hourly deterministic monitor plus immediate milestones/blockers/final in original Telegram topic. Do not add 15-minute LLM polling.
- Log role/profile/provider/model/effort/rights/budgets BEFORE dispatch; collect actual launches and process metrics, failures/rework/owner questions. Separate configured/observed/unavailable.

## Authority
Local project writes, builds/tests, simulator operations and in-scope Git branches/commits/push/PR/merge allowed. Default new remote private if needed; no public release, costs, secret/access changes, unrelated files/services, other profile modifications. Dedicated repo path intended: /Users/agent/hermes-clean-20260903/projects/web-native-bridge-lab. Delivery coordinator has acceptance ownership; do not make owner operate agents.

## Final artifact
Runnable repo/RC with succinct README, reproducible clean lifecycle commands, validated OpenSpec, tests/security/Simulator evidence tied to exact candidate, known limits/next opportunities, clean board/worktrees/main, and honest agent-flow/model/effort report. All started project servers stopped on handoff. Avoid rich media noise; store optional screenshots as evidence files.
