# Web–Native Bridge Lab — PER-85

## Source of truth
Read docs/agent/OWNER_MISSION.md. The owner approved this bounded mission; Hermes coordinates product acceptance. OpenSpec behavior/specs/tests are English; reviewer and owner summaries may be Russian. This is a small serious foundation, not production-ready and not a disposable spike.

## Boundaries
Work only in your own assigned project worktree and scoped task paths. First verify actual terminal cwd, file-tool paths, Git common-dir, branch, task/board/project/model/provider/effort bindings. An unexpected initial cwd is NOT permission to write elsewhere: explicitly cd to the assigned absolute workspace and verify before file writes. No Hermes core/config/profile changes, other-project writes, secrets, unrelated processes, public release or deployments. Do not disable approvals or security hooks. No child agents from implementation/review workers.

## Delivery
- Canary comes before the full immutable mission graph. Only the default-profile coordinator invokes the accepted external graph builder; dispatched workers have a pinned board DB override and must not bypass its guard or create replacement graphs.
- Default code implementation AND same-card review are explicitly pinned Sol/high unless this card says otherwise. Planning and independent final acceptance use explicit Astra routing. request_review preserves overrides: do NOT infer reviewer model from its profile or mutate routing after opening review dispatch. No profile edits.
- Every code-changing card requests independent same-card review via iosverifier; the reviewer either requests changes or completes. No implementation self-completion. Maximum two same-root-cause rework cycles before technical replanning.
- Budgets are 20–40 planned tool iterations, never over60 without splitting; save evidence and block/replan before exhaustion. These are policy budgets, not proven runtime hard limits. Rights are not an OS sandbox.
- Read parent completion evidence and merge their reviewed commits into YOUR own worktree before implementation. Do not assume primary main contains upstream work. Preserve parent commit identity; no unrelated cherry-picks or raw Kanban repair.
- Technical in-scope commits, local merges and reviewed private PRs are allowed. Only final synthesis/coordinator updates primary main. No public publication, auth, financial or new owner-scope decisions.
- Every handoff names exact head/branch, changed paths, command-backed tests and limitations. Review completion preserves the verified head for downstream tasks.
- Specs require independent review before dependent implementation; source/tests/specs must agree at final acceptance. Do not archive or claim completion before tests and independent gates.

## Lifecycle
Services are opt-in and bound to loopback, with documented start/status/stop and tracked owned children. No permanent daemon, autostart, broad process kills or secret-bearing requests. Port conflicts must not disturb foreign processes. Always stop owned test services and verify ports released. Temporary build/evidence paths stay in ignored project directories. Simulator-only acceptance uses a dedicated project simulator where practical.
