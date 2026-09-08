# Foundation validation evidence — t_f953e777

Scope: draft specification/protocol/architecture artifacts only. Independent review is pending; this is not runtime product acceptance. No native/iOS/web/backend module was implemented, built or exercised. No project listener or Simulator was started. The graph and other worktrees remain untouched.

Branch: `web-native-bridge-lab/t_f953e777-per-85-foundation-deliverylead`. Base: seed `07edbe1`; the card has no parents. Exact resulting commit is recorded in the same-card review metadata (avoids a self-referential hash). All commands ran in the assigned t_f953e777 worktree.

## Executed checks

### toolchain

Command: `node --version && npm --version && openspec/tooling/node_modules/.bin/openspec --version`

Exit: 0

```text
v26.5.0
11.17.0
1.12.0
```

### locked-install

Command: `npm ci --prefix openspec/tooling --ignore-scripts --no-audit --no-fund --cache "$PWD/.artifacts/npm-cache"`

Exit: 0

```text
added 85 packages in 689ms
```

### openspec

Command: `OPENSPEC_TELEMETRY=0 OPENSPEC_NO_COMPLETIONS=1 openspec/tooling/node_modules/.bin/openspec validate --all --strict --no-interactive --json`

Exit: 0

```text
{
  "items": [
    {
      "id": "add-bridge-lab",
      "type": "change",
      "valid": true,
      "issues": [],
      "durationMs": 10
    }
  ],
  "summary": {
    "totals": {
      "items": 1,
      "passed": 1,
      "failed": 0
    },
    "byType": {
      "change": {
        "items": 1,
        "passed": 1,
        "failed": 0
      },
      "spec": {
        "items": 0,
        "passed": 0,
        "failed": 0
      }
    }
  }
}
```

### artifact-status

Command: `OPENSPEC_TELEMETRY=0 OPENSPEC_NO_COMPLETIONS=1 openspec/tooling/node_modules/.bin/openspec status --change add-bridge-lab --json`

Exit: 0

```text
{
  "schemaName": "spec-driven",
  "isPlanningComplete": true,
  "artifacts": [
    {
      "id": "proposal",
      "outputPath": "proposal.md",
      "status": "done",
      "requires": []
    },
    {
      "id": "specs",
      "outputPath": "specs/**/*.md",
      "status": "done",
      "requires": [
        "proposal"
      ]
    },
    {
      "id": "design",
      "outputPath": "design.md",
      "status": "done",
      "requires": [
        "proposal"
      ]
    },
    {
      "id": "tasks",
      "outputPath": "tasks.md",
      "status": "done",
      "requires": [
        "specs",
        "design"
      ]
    }
  ]
}
```

### schema

Command: `node protocol/v1/validate.cjs`

Exit: 0

```text
valid: 14 classifications PASS
invalid: 15 classifications PASS
semanticOnly: 7 classifications PASS
Schema compiled; 36 vectors PASS. Semantic-only expected error codes were NOT runtime-tested.
```

### syntax

Command: `node --check protocol/v1/validate.cjs`

Exit: 0

```text
(no output)
```

### whitespace

Command: `git diff --check`

Exit: 0

```text
(no output)
```

## Interpretation and downstream inputs

OpenSpec reports one valid change, four artifact categories present and no issues. This is artifact completeness, not checked implementation tasks or acceptance. Ajv validates 36 example classifications, including structural rejection examples and seven structurally valid semantic vectors; their expected network/lifecycle error codes were NOT runtime-tested. Unit, HTTP, WebKit, Simulator, service lifecycle and same-binary gates remain planned in docs/verification-plan.md.

The reviewer must independently inspect protocol/v1/README.md, schema.json and examples.json together, the four capability deltas, docs/architecture.md and the matrix; rerun the commands above on the exact candidate. Particular review focus: per-document hello/session binding with old queued messages, error precedence versus schema/UTF-8 byte limits, reject-all redirect semantics, bounded cancellation/deadline/response behavior, and exact A/B fixture/build interfaces.

After reviewer approval, backend/web/transport workers merge the approved head into their own worktrees; iOS also merges the reviewed transport head. Module paths and API/fixture/build/port/lifecycle decisions are pinned in architecture and protocol documents. Do not widen network policy or silently modify these shared contracts. Runtime module workers own RED/GREEN tests; the foundation added artifact validation only, not production code.

No archive, canonical spec promotion, main merge, publication, profile/model change, or owner RC acceptance occurred.
