# Explain v2 runtime evidence

Candidate phase: R implementation evidence. The runtime harness and retained artifacts below are Simulator-only engineering proof. They do not constitute independent final acceptance A, owner RC acceptance, primary-main integration, OpenSpec archive authorization, production hosting, or real-device evidence.

## Source-state ledger

- Branch: `web-native-bridge-lab/t_d9bcf406-per-85-explain-v2-runtime-implementer`.
- Reviewed N parent: `2a90459975aa1923f65adcfcc8682da620f5dbef`.
- First committed R code candidate: `47c1d754b02c1b2a7b9d7d451d7a5d95d259b3d7`.
- First review-hardening commit: `26580c85ce21453f87280025c53daf831f276f68`.
- Cleanup/state-matrix correction: `c15e62653861fa7d9bc7774078059bfe277a3375`.
- Five-width expansion: `3015179744842c6d4ef0fce75c879bee2b000e56`.
- Exact runtime candidate with pending-disablement assertion: `eafb120fbaf9316955798e98d5d1e4e71d92ba28`. The fresh `source.json` records that exact SHA and an empty `working_diff`. This replaces the earlier dirty-source limitation for the primary Explain runtime proof; independent same-card review and final A remain separate obligations.

Machine-readable facts are in [runtime-evidence.json](runtime-evidence.json). Ignored raw artifacts are rooted at `.artifacts/verify-simulator-explain-v2-c72da8b135/` while this worktree is retained.

## Successful real-runtime sweep

At `2026-09-10 00:49 +04`, `scripts/verify simulator-explain-v2` ran from exact-clean `eafb120` and exited 0. `result.json` records `explain_v2_runtime: PASS`, `final_acceptance: false`, one owned iPhone 17 Pro Simulator (`2D46586E-F7AE-4D2C-8E7D-D95173C17899`, iOS 26.5), and successful cleanup. Six xcresults were independently read: 42 focused native tests plus one A state-matrix test, one assistive-layout test, one B cold/repeat test, one B retry-matrix test, and one installed-shell UI test; every bundle recorded zero failures and zero skips.

The run built actual distinct assets:

- A entry `assets/index-B02rsMN0.js`: `647633da29c7ce1b8518b1e9928e42030d9834d0b31c96a662aac10d49dc15ff`.
- B entry `assets/index-BQCeerPS.js`: `4709a62a193c3ae47336a5d8cc09eb4645f31caa893048e7c86cc830a1152cf5`.
- Shared CSS `assets/index-BUSlcUzb.css`: `5485f28ff3fa7a9155600790bd1aefba2f0a4a4f6064210634eec3e475b0ce47`.

The production shell was installed once. Before A, after A, after B, and after all Explain faults, the app container and all three installed-file hashes remained equal. The executable SHA-256 was `b33f7dab37b88d93360386fd3e7533333cbe7994cbc64af0da521266cde8ded9`; the sorted installed manifest digest was `a962e3c107b139c468edea3511be902b5fd4aff57bc218aa5d00ce02b44fcdcd`. No native build, reinstall, or app launch occurred between A and B.

The attributable backend slice contains exactly one `GET /api/catalog 200 tag=scenario-a` and four `POST /api/quote 200 tag=scenario-b` events: initial B, recovered API retry, cold B after diagnostics return, and repeat. Static control traffic stayed on port 8787. During the unavailable-API fault, the owned lab stopped, both ports were verified free, and a static-only server exposed the real B assets on 8787 while 8788 remained unavailable. Retry occurred only after the owned lab restarted. The missing-entry fault moved the actual B entry aside, observed `GET /assets/index-BQCeerPS.js 404`, then restored the exact hashed file and recovered via native reload.

## Layout and visual inspection

The component tests loaded the actual emitted A/B roots through the production WK adapter into explicit WKWebView content frames at 320, 390, 430, 768, and 1100 CSS px. The A matrix retained introduction, real pending, catalog result, unchanged-A and final-comparison observations at all five widths; the B matrix covered cold and quote-result states at all five widths; a static-real-web/API-unavailable setup retained retry/error observations at all five widths. Every observation reset scroll to zero, asserted no horizontal overflow, ordered non-overlapping route/current/action frames and a >=44-point action. Pending alone intentionally retained and asserted a disabled action. The exported manifests contain 25 A screenshots plus 25 geometry files, 10 B screenshots plus 10 geometry files, and 5 retry screenshots plus 5 geometry files. A separate assistive test enabled Reduce Motion, observed `animation-name: none`, applied 1.6× test-local root text scale, asserted vertical rather than horizontal overflow, preserved the explanatory route text, and reached the action by scrolling.

The retained 320×740 and 1100×900 screenshots were inspected, not accepted solely from test status. macOS Vision OCR on the corrected artifacts confirmed visible Russian pending copy and disabled `Ждём ответ...`, final `Расчёт получен` content with `12,00 $` and `Рассчитать снова`, and the unavailable-API copy with `Повторить расчёт` at both narrow and wide widths. The geometry attachments report zero horizontal overflow, scroll from Y=0, and no route/current/action overlap. The enlarged component screenshot remains intentionally captured after scrolling to the action; it proves readable content/action at that scroll position, not simultaneous initial visibility of the route and action.

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
| EX-07 | Real WK frames, geometry and screenshots cover A introduction/pending/catalog/unchanged/final-comparison, B cold/quote-result, and real API-unavailable retry at 320/390/430/768/1100. Reduced motion and enlarged component text pass; installed safe-area/footer/action frames and `accessibility-extra-large` vertical scrolling remain retained. | Implementer PASS with enlarged-screenshot scope noted |
| EX-08 | The new mode uses production client/adapter and static-only host control; installed app/container equality and backend attribution are recorded. Unit, fresh 15-test harness, fresh operations and proportional Stage2/3 gates pass. Mature Stage4 remains retained because R changes no product native source. | Implementer PASS; independent review pending |

## Failed attempts and corrections retained

Three earlier Explain sweeps reached the installed UI test and exited 65 while cleaning every owned service and Simulator:

- `verify-simulator-explain-v2-d764d14575`: an assertion incorrectly required the enlarged heading to move after a swipe before the content-size setting was applied.
- `verify-simulator-explain-v2-26c87f65e5`: the same brittle scroll-position assertion remained even though the action itself was reachable.
- `verify-simulator-explain-v2-90a8bbb40d`: the content-size command succeeded, but the already-running application did not adopt it; footer height remained 14.33 points.

The final flow relaunches the same installed app after changing Simulator content size, then verifies that the native footer height increases and the web action is reachable. It does not reinstall or rebuild the app. All failed-run `cleanup.json` records contain no errors and report owned services stopped and owned Simulators removed.

The Kanban run later timed out at 5,423 seconds while a duplicate post-commit operations sweep was still running. This was not a product or review failure. The earlier operations run had already exited 0; the coordinator verified no worker/test descendants, all recorded Simulator UDIDs absent, and ports 8787/8788 free.

## Other executed gates and limits

- `python3 -m unittest scripts.tests.test_verify.EvidenceTests.test_missing_entry_fault_is_cleanup_eligible_before_and_after_interrupted_move -v` — RED before the ownership-order fix, then PASS.
- `python3 -m unittest discover -s scripts/tests -v` — PASS after adding the deterministic missing-entry move interruption regression.
- `scripts/verify unit` — exact-clean `eafb120`, fresh exit 0, `.artifacts/verify-unit-d1869b9b03/`; includes strict OpenSpec, protocol/backend/native/iOS/web tests, audit, typecheck, builds, all 15 harness tests, and diff check.
- `python3 scripts/tests/operations.py` — fresh exit 0, `.artifacts/verify-stage5-operations-bf8a12811b/`; expected interrupt/failure children cleaned their owned resources, recorded Simulators were absent, and ports 8787/8788 were free.
- `scripts/verify simulator-stage5-production-ux` — exit 0, `.artifacts/verify-simulator-stage5-production-ux-b20c1cac4f/`; 42 native tests plus one installed UI test, zero failures/skips, same container/manifest, owned teardown.
- `scripts/verify simulator-stage2-outcomes` — fresh exit 0, `.artifacts/verify-simulator-stage2-outcomes-0c845d4b42/`; Stage2 outcomes PASS, same container/manifest, owned services stopped and owned Simulator removed.
- `scripts/verify simulator-stage3-trust-limits` — fresh exit 0, `.artifacts/verify-simulator-stage3-trust-limits-ad9e904ef1/`; Stage3 trust/limits PASS, same container/manifest, owned services stopped and owned Simulator removed.
- Stage4 was not rerun in R: the diff from reviewed N contains no `ios/Sources`, transport, policy, backend, or protocol production changes. Its reviewed 53-test N evidence remains the proportional lifecycle/privacy baseline.
- Cleanup for the exact-clean Explain rerun records no errors, both owned services stopped, and the owned Simulator removed; post-run checks also found ports 8787/8788 free and the recorded Simulator absent.
- No real device, cloud, authentication, secrets, production deployment, publication, or App Store path was exercised. Independent same-card review, final A and owner acceptance remain pending.
