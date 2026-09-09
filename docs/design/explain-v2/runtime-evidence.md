# Explain v2 runtime evidence

Candidate phase: R implementation evidence. The runtime harness and retained artifacts below are Simulator-only engineering proof. They do not constitute independent final acceptance A, owner RC acceptance, primary-main integration, OpenSpec archive authorization, production hosting, or real-device evidence.

## Source-state ledger

- Branch: `web-native-bridge-lab/t_d9bcf406-per-85-explain-v2-runtime-implementer`.
- Reviewed N parent: `2a90459975aa1923f65adcfcc8682da620f5dbef`.
- First committed R code candidate: `47c1d754b02c1b2a7b9d7d451d7a5d95d259b3d7`.
- The successful `simulator-explain-v2` run began before commit. Its `source.json` therefore records the N parent plus a dirty tracked diff, not `47c1d75` as an exact clean source SHA. At that point the new layout file was untracked and consequently absent from `git diff --stat`; README/task reconciliation was written after the sweep. The tested code/test/runner files had been written before the successful XCTest execution and were then committed, but this timing is not a cryptographic exact-head proof.
- The successful initial unit, operations, Explain, and Stage5 exits were recovered from the original run session after the Kanban worker timed out during a duplicate operations rerun. The coordinator independently read the retained xcresults and repeated the runner tests. This R pass then added a deterministic regression for the interruptible `lab-start` ownership window and freshly reran the full unit gate (including all 14 harness tests), Stage5 operations, and proportional Stage2/3 Simulator gates. Their `source.json` records `47c1d75` plus the tracked R reconciliation/ownership diff; the new evidence documents were still untracked and therefore absent from that diff summary. Exact clean final-head verification remains an obligation of independent same-card review/final A; this record does not relabel the precommit Explain run as exact-head acceptance.

Machine-readable facts are in [runtime-evidence.json](runtime-evidence.json). Ignored raw artifacts are rooted at `.artifacts/verify-simulator-explain-v2-5871b54ed6/` while this worktree is retained.

## Successful real-runtime sweep

`scripts/verify simulator-explain-v2` exited 0 and produced `result.json` with `explain_v2_runtime: PASS`, `final_acceptance: false`, one owned iPhone 17 Pro Simulator (`E9737698-FEC9-4FD8-B497-4B4A01A7672B`, iOS 26.5), and successful cleanup. Five xcresults were independently read: 42 focused native tests plus one A-layout, one assistive-layout, one B-layout, and one installed-shell UI test; every bundle recorded zero failures and zero skips.

The run built actual distinct assets:

- A entry `assets/index-B02rsMN0.js`: `647633da29c7ce1b8518b1e9928e42030d9834d0b31c96a662aac10d49dc15ff`.
- B entry `assets/index-BQCeerPS.js`: `4709a62a193c3ae47336a5d8cc09eb4645f31caa893048e7c86cc830a1152cf5`.
- Shared CSS `assets/index-BUSlcUzb.css`: `5485f28ff3fa7a9155600790bd1aefba2f0a4a4f6064210634eec3e475b0ce47`.

The production shell was installed once. Before A, after A, after B, and after all Explain faults, the app container and all three installed-file hashes remained equal. The executable SHA-256 was `15d48f315744f0205b2bb955f00a9600de9b1a1c344c129bbe4817186fc7e1d0`; the sorted installed manifest digest was `62b2c916dcc23fd39de47430c05d004f0fba9c11f78bb66a25d0bb75fc06e4da`. No native build, reinstall, or app launch occurred between A and B.

The attributable backend slice contains exactly one `GET /api/catalog 200 tag=scenario-a` and four `POST /api/quote 200 tag=scenario-b` events: initial B, recovered API retry, cold B after diagnostics return, and repeat. Static control traffic stayed on port 8787. During the unavailable-API fault, the owned lab stopped, both ports were verified free, and a static-only server exposed the real B assets on 8787 while 8788 remained unavailable. Retry occurred only after the owned lab restarted. The missing-entry fault moved the actual B entry aside, observed `GET /assets/index-BQCeerPS.js 404`, then restored the exact hashed file and recovered via native reload.

## Layout and visual inspection

The component tests loaded the actual emitted A/B roots through the production WK adapter into explicit WKWebView content frames of 320×740, 390×844, and 1100×900. They reset scroll to zero, asserted no horizontal overflow, ordered non-overlapping route/current/action frames, a visible >=44-point action, and retained screenshots plus geometry attachments for A introduction, A catalog result, unchanged A, cold B, and B quote result. A separate assistive test enabled the owned Simulator's Reduce Motion setting, observed `animation-name: none`, applied 1.6× test-local root text scale, asserted vertical rather than horizontal overflow, preserved the explanatory route text, and reached the action by scrolling.

The retained 320×740 and 1100×900 screenshots were inspected, not accepted solely from test status. They visibly contain the complete Russian header, A/B built identity, three-role route, truthful current state and one action without overlap. The catalog and quote values remain readable, and the 1100-wide composition does not stretch the content into detached columns. The enlarged component screenshot was intentionally captured after scrolling to the action; it proves readable content/action at that scroll position, not simultaneous initial visibility of the route and action.

The installed UI evidence used the actual 402×874 iPhone 17 Pro shell. Accessibility trees place the WKWebView below the top chrome and above the native footer; the Bundle label is `Версия приложения 1.0 · сборка 1`. Default A, unchanged A, and B-result screenshots keep the route and current action visible with the footer outside the web content. The unavailable-API screenshot shows the adjacent retry and no stale success. The missing-entry screenshot shows the static Russian fallback and native reload/footer, with no business action. At `accessibility-extra-large`, the native header/footer enlarge, the web viewport shrinks, and the retained screenshot/tree show a reachable quote action through vertical scrolling without horizontal overflow. The test does not claim that the full enlarged journey fits at scroll top.

Two success-bundle issue attachments are iOS framework warnings about private `_UIGravityWellEffectAnchorView`/`_UIReparentingView` insertion around the SwiftUI context menu. They did not fail the test, but remain disclosed for reviewer inspection rather than being hidden.

## EX-01–08 evidence map

| Contract | R evidence and retained proof | Status before independent review |
|---|---|---|
| EX-01 | Real A/B installed screenshots and WK snapshots show the Russian introduction, persistent Screen → Application → Server route, adjacent state/result, one main action, and no Diagnostics controls in the demo. | Implementer PASS |
| EX-02 | Component pending recorder observes actual disabled `Ждём ответ…`, forward direction and no required delay; installed catalog/quote and actual document reloads resolve from real responses. Mature N Stage4 lifecycle proof is retained because R changed no product native source. | Implementer PASS; exact-head review pending |
| EX-03 | Real returned Notebook and quote `quantity=2`, `totalMinor=1200`, `USD` drive UI; stopped API produces `Не удалось связаться с сервером`, adjacent retry, and a fresh successful quote. Unit/Stage5 retain category/body/cancel behavior. | Implementer PASS |
| EX-04 | A has no quote; same-A reload reports `Загружен прежний веб-экран`; real served B replacement exposes quote on the unchanged installed app; cold B omits catalog history and repeat stays B. | Implementer PASS |
| EX-05 | Visible A/B labels use the distinct emitted entry paths; installed Bundle identity is 1.0/1; external container and complete installed-file equality supply the same-binary evidence rather than UI labels. | Implementer PASS |
| EX-06 | Removing the actual B JS entry yields a real 404 and static `Веб-экран не запустился` fallback with no business action; restoring the exact entry and native reload recovers without reinstall. N route-preserving native failure tests remain unchanged. | Implementer PASS |
| EX-07 | Real WK frames and screenshots cover all three required content sizes; reduced motion and enlarged component text pass; installed safe-area/footer/action frames and `accessibility-extra-large` vertical scrolling are retained in screenshots/trees. | Implementer PASS with enlarged-screenshot scope noted |
| EX-08 | The new mode uses production client/adapter and static-only host control; installed app/container equality and backend attribution are recorded. Unit, fresh 14-test harness, fresh operations and proportional Stage2/3 gates pass. Mature Stage4 remains retained because R changes no product native source. | Implementer PASS; independent review pending |

## Failed attempts and corrections retained

Three earlier Explain sweeps reached the installed UI test and exited 65 while cleaning every owned service and Simulator:

- `verify-simulator-explain-v2-d764d14575`: an assertion incorrectly required the enlarged heading to move after a swipe before the content-size setting was applied.
- `verify-simulator-explain-v2-26c87f65e5`: the same brittle scroll-position assertion remained even though the action itself was reachable.
- `verify-simulator-explain-v2-90a8bbb40d`: the content-size command succeeded, but the already-running application did not adopt it; footer height remained 14.33 points.

The final flow relaunches the same installed app after changing Simulator content size, then verifies that the native footer height increases and the web action is reachable. It does not reinstall or rebuild the app. All failed-run `cleanup.json` records contain no errors and report owned services stopped and owned Simulators removed.

The Kanban run later timed out at 5,423 seconds while a duplicate post-commit operations sweep was still running. This was not a product or review failure. The earlier operations run had already exited 0; the coordinator verified no worker/test descendants, all recorded Simulator UDIDs absent, and ports 8787/8788 free.

## Other executed gates and limits

- `python3 -m unittest discover -s scripts/tests -v` — PASS, 14 tests after the `lab-start` ownership regression.
- `scripts/verify unit` — fresh exit 0, `.artifacts/verify-unit-d331387f96/`; includes strict OpenSpec, protocol/backend/native/iOS/web tests, audit, typecheck, builds, all 14 harness tests, and diff check.
- `python3 scripts/tests/operations.py` — fresh exit 0, `.artifacts/verify-stage5-operations-bf8a12811b/`; expected interrupt/failure children cleaned their owned resources, recorded Simulators were absent, and ports 8787/8788 were free.
- `scripts/verify simulator-stage5-production-ux` — exit 0, `.artifacts/verify-simulator-stage5-production-ux-b20c1cac4f/`; 42 native tests plus one installed UI test, zero failures/skips, same container/manifest, owned teardown.
- `scripts/verify simulator-stage2-outcomes` — fresh exit 0, `.artifacts/verify-simulator-stage2-outcomes-0c845d4b42/`; Stage2 outcomes PASS, same container/manifest, owned services stopped and owned Simulator removed.
- `scripts/verify simulator-stage3-trust-limits` — fresh exit 0, `.artifacts/verify-simulator-stage3-trust-limits-ad9e904ef1/`; Stage3 trust/limits PASS, same container/manifest, owned services stopped and owned Simulator removed.
- Stage4 was not rerun in R: the diff from reviewed N contains no `ios/Sources`, transport, policy, backend, or protocol production changes. Its reviewed 53-test N evidence remains the proportional lifecycle/privacy baseline.
- No real device, cloud, authentication, secrets, production deployment, publication, or App Store path was exercised. Final A and owner acceptance remain pending.
