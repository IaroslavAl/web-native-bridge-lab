# WB-01 numeric rework — run 73

Candidate for fresh same-card independent review, not product acceptance. Task `t_b5aeb77f`, board `web-native-bridge-lab`, project declaration `p_ce173eae`. Coordinator explicitly authorized numeric-only rework after reviewer run 72; accepted lifecycle design is unchanged.

## Scope and cause

Entry head: `a1af0b71065ce438442d0063dbc4b106ce100297`.
Branch: `web-native-bridge-lab/t_b5aeb77f-per-85-ios-bridge-implementer`.
Workspace: `/Users/agent/hermes-clean-20260903/projects/web-native-bridge-lab/.worktrees/t_b5aeb77f`.
Git common directory: `/Users/agent/hermes-clean-20260903/projects/web-native-bridge-lab/.git`.
Approved parents `b5c5423c585b8599f5639075e5c40c8a5f517ada` and `e9f338142735b754362c59ed62ad1fa8450c0b4e` remain ancestors; their independent completion metadata was read. No merge was necessary. Entry worktree was clean. Actual parent-process argv confirmed iosimplementer / openai-codex / gpt-6-astra / high; no routing changes.

`BridgeEngine.integer` compared a Double against inclusive `Double(Int.max)`, which rounds upward to 2^63, then called the trapping Int initializer. Replaced only that conversion/check with `Int(exactly: number.doubleValue)`. It is failable for overflow, non-finite or fractional Double values. Existing NSNumber boolean rejection and caller-specific version/id/timeout validation remain unchanged. No native transport, coordinator, adapter, project, web/backend or specification changes.

This intentionally retains Foundation/Double numeric interpretation, not an arbitrary-precision lexical JSON parser. For example, a negative integer token adjacent to Int.min can round to Int.min; the timeout remains rejected by transport range validation and ids remain rejected by their bounds. Valid protocol numbers are small exactly representable integers. Error precedence and existing structural-versus-semantic id-consumption ownership are preserved.

## Regressions and chronology

Added seven XCTest methods to the existing `BridgeEngineTests.swift`, already included in both package and Xcode targets:

- The attached reviewer's two exact raw inputs (`v=9223372036854775808`, unknown envelope with recovered `id=9223372036854775808`) reproduced independently BEFORE the fix: each filtered package execution exited 1, xctest signal 5, `Fatal error: Double value cannot be converted to Int because the result would be greater than Int.max`. Both pass after the fix, with exact id/code and zero executor submissions.
- Version matrix: positive/negative huge values, adjacent Int boundaries and neighboring representable Doubles, zero/future version, booleans, fraction, string/null; unsupported version precedes malformed shape/session and retains recoverable id 7. Numeric `1`, `1.0`, `1e0` remain accepted.
- Request/cancel/unknown id matrix: huge and neighboring values, -1/0/max+1, booleans/fraction/string/null; null recovery, zero submissions/cancel calls and subsequent valid id 1 admission.
- Malformed/overflow timeout matrix: id 1 recovered, zero submissions and id 1 not consumed.
- Representable timeout range errors: real HTTPExecutor returns `Request timeout is invalid` before URL policy, then duplicate id returns bridge structural error. Denied URL is a safety backstop; no sockets are created. This preserves semantic failure consumption, distinct from malformed numeric structure.
- Valid id 1/max-1/max and timeout 1/29999/30000 with decimal/exponent integral notation reach the recording executor exactly; maximum cancel id is retained.

The five broader matrix/control tests passed the corrected implementation on first execution; they are not claimed as additional pre-fix RED reproductions. Tests use in-memory isolated executors and no shared server, files or ports.

## Executed gates

All commands from workspace root; logs under ignored, disposable `.artifacts/ios-numeric/`. This committed record and exact-head review metadata are durable.

| Command | Result / log |
| --- | --- |
| `swift test --package-path ios -Xswiftc -warnings-as-errors --filter BridgeEngineTests/testHugeVersionReturnsUnsupportedWithoutTrapping` before fix | Expected crash above; `red-version.log` |
| Same command with `testHugeRecoveredIDReturnsInvalidWithoutTrapping` before fix | Expected crash above; `red-id.log` |
| `swift test --package-path ios -Xswiftc -warnings-as-errors --filter 'BridgeEngineTests/testHuge'` after fix | 2 passed; `green-repro.log` |
| `swift test --package-path ios -Xswiftc -warnings-as-errors` | 19 passed, 0 failed; `ios.log` |
| `swift test --package-path native/TransportPackage -Xswiftc -warnings-as-errors` | 39 passed, 0 failed; `native.log` |
| Full Xcode Simulator test below | 42 passed, 0 failed/skipped, independently parsed xcresult summary; `full.log`, `full.xcresult` |
| Generic Simulator build below | PASS universal arm64/x86_64; `generic.log` |
| Generic Simulator analyze below | PASS; `analyze.log` |
| `node protocol/v1/validate.cjs` | 36 structural classifications: 14 valid, 15 invalid, 7 semanticOnly; not runtime semantic execution; `protocol.log` |
| `OPENSPEC_TELEMETRY=0 OPENSPEC_NO_COMPLETIONS=1 openspec/tooling/node_modules/.bin/openspec validate --all --strict --no-interactive --json` | 1 valid change, 0 failures; `openspec.json` |
| `git diff --check`; `plutil -lint ios/BridgeLab/Info.plist ios/BridgeLab.xcodeproj/project.pbxproj`; `xmllint --noout ios/BridgeLab.xcodeproj/xcshareddata/xcschemes/BridgeLab.xcscheme` | PASS |

Xcode 26.6 (17F113), dedicated iPhone 17 Pro / iOS 26.5 / arm64. Full suite includes all unchanged adapter/lifecycle tests.

    xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab -destination 'platform=iOS Simulator,id=5BC918D6-C380-42F3-BDAB-DEDD35962E34' -derivedDataPath "$PWD/.artifacts/ios-numeric/derived" -resultBundlePath "$PWD/.artifacts/ios-numeric/full.xcresult" CODE_SIGNING_ALLOWED=NO test
    xcrun xcresulttool get test-results summary --path .artifacts/ios-numeric/full.xcresult --format json
    xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab -destination 'generic/platform=iOS Simulator' -derivedDataPath "$PWD/.artifacts/ios-numeric/generic" CODE_SIGNING_ALLOWED=NO build
    xcodebuild -project ios/BridgeLab.xcodeproj -scheme BridgeLab -destination 'generic/platform=iOS Simulator' -derivedDataPath "$PWD/.artifacts/ios-numeric/analyze" CODE_SIGNING_ALLOWED=NO analyze

Reproduction requires a new owned Simulator and fresh result-bundle path. Recorded device was already Shutdown after testing (shutdown returned 405), then deleted and verified absent by fresh simctl JSON. Other Simulators were untouched. No backend, fixed-port services, permanent daemon, remote CI, GitHub/Jira, main merge or publication.

Xcode emitted AppIntents metadata extraction warnings and signed XCTest-framework stripping warnings; package warnings-as-errors passed. No warnings-free Xcode claim.

## App and downstream

App: `.artifacts/ios-numeric/generic/Build/Products/Debug-iphonesimulator/BridgeLab.app`.
Executable SHA-256: `82f0e3c4eceed8f5b7e4db9a22c47d039c2922120e1b27f68f83f6100ddd14b8`.
Build/app/xcresult are disposable; commands and observed hash remain here. Different build paths may produce different hashes. This is not same-installed-binary A/B evidence.

The exact resulting candidate SHA is on the same-card review transition. After independent approval only, integration `t_9d8fd391` merges that exact head preserving parent identity and combines separately approved web/backend heads. Child inspected and still coordinator-scheduled. Shipping origins remain page `http://127.0.0.1:8787`, API `http://127.0.0.1:8788`; reproduction/accessibility hooks are in `README.md`. Prior aggregate implementation coverage and limitations remain in `LIFECYCLE_STAGE_B.md`.

Real React/WKWebView/backend flow, actual iframe provenance, populated synthetic credential-store and socket effects, and unchanged installed binary A/B remain downstream. This numeric rework does not approve the whole mission, archive OpenSpec or replace independent review.
