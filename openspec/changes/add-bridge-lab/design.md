## Context

The seed contains no application modules. The approved mission requires a maintainable Simulator lab, not production readiness. The immutable delivery graph already exists: foundation review precedes parallel backend/transport/web, iOS follows reviewed transport, integration joins the reviewed modules, independent acceptance follows the exact RC.

## Goals / Non-Goals

Goals: generic native HTTP, web-only business interpretation, bounded trust/lifecycle behavior, reproducible real WebKit proof, and small independently testable modules.

Non-goals: production authentication, arbitrary origins, streaming/binary/files, retry/cache platform, device signing, cloud/public release and a full UI platform. See the frozen owner mission for the complete boundary.

## Decisions

- Normative wire/security limits live once in `protocol/v1/README.md` with closed draft-07 `schema.json` and labeled conformance vectors. Requirements below refer to those exact rules; schema alone is not policy proof.
- Use reply-capable WebKit message handling with a JSON-string input bounded before parsing and structured-object replies, rather than eval callbacks. Native-generated document generation plus monotonically increasing per-document request ids prevents cross-document replay without unbounded tombstones.
- Use Foundation URLSession in `native/TransportPackage`, not domain-specific native clients or a third-party network library. Stream delegate data internally to enforce a bounded text response; this is not a public streaming API.
- Separate fixed page and API origins; reject every redirect instead of designing a multi-hop policy. Ephemeral credential-free resources and narrow headers avoid accidental native privilege inheritance.
- Pin module paths, public Swift seam, fixed ports, fixture formats, web build commands and test hooks in `docs/architecture.md`. Backend owns scripts/lab; integration owns scripts/verify and root run instructions. No shared mutable module manifests.
- Use Node built-ins for synthetic fixtures and React/TypeScript/Vite for built web assets. Swift package plus checked-in Simulator Xcode project gives a small platform-native build. Workers pin their own dependencies/lockfiles inside their modules.
- Integration proves both visible web behavior and backend requests before/after web asset replacement, retaining hashes of the same installed executable and bundle. A mock Promise or browser fetch cannot satisfy acceptance.

## Risks / Trade-offs

- Plain loopback HTTP and trusted served JavaScript are a lab-only trust model, not production bootstrap security.
- Cancellation cannot roll back remote side effects. Deadline/cancel results use a serialized first-terminal rule and cannot race into a second reply.
- Application byte caps do not bound every OS HTTP parser/decompressor allocation; reject unsupported payloads and disclose this limit.
- Real WebKit provenance, lifecycle and ATS behavior need actual Simulator verification, not only schema or native mocks.
- Fixed ports require exclusive serialized acceptance; module tests inject isolated resources. Port conflicts must fail without disturbing foreign processes.
- Strict bounds and narrow headers intentionally reduce flexibility to keep the first contract small. Future capability expansion needs a new reviewed delta/version strategy, not silent widening.

## Rollout / rollback and review

No deployment or data migration exists. Review this same foundation card before downstream implementation. Each code card receives independent same-card review. Integration can roll back by serving build A again without reinstalling the app, then stops owned resources. Do not archive the active OpenSpec change or mark product tasks complete until real gates and independent acceptance pass; coordinator retains final reconciliation and owner handoff.

## Open questions

None requiring a product decision. Implementation findings that contradict this seam require a precise reviewed contract correction; they do not authorize a new product outcome.
