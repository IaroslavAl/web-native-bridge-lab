# PER-85 Explain v2 — authorized follow-up mission

Status: implementation authorized; this packet is a design/spec handoff awaiting independent same-card technical review, NOT an implemented UI or accepted RC.

## Authorization and baseline

Task `t_9cc1179b`, board `web-native-bridge-lab`, project `p_ce173eae` records the owner's selection of Explain, continuation to v2, and explicit permission to implement. This supersedes historical design-only language in the retained mockup brief. The accepted technical foundation is commit `778fbb7738212ab817a23aea80685dc1d49cfd78`; the owner already observed A catalog → B quote on the same installed Simulator app. Do not redo the foundation or original immutable mission graph. This is a standalone follow-up; only the coordinator creates its later execution cards.

## Frozen product outcome

Deliver a bright, concise Russian explanation for non-developer colleagues: introduction → real catalog request/result → presenter separately replaces served web assets → participant loads them → real quote for two notebooks → visible changed web capability alongside unchanged installed application. Keep the Screen → Application → Server route visible, show request/response direction, and keep the single primary action next to loading/error/result. Native stays generic; HTTP, business interpretation and trust boundaries remain as defined by OWNER_MISSION.md and protocol/v1.

The new implementation SHALL use actual responses and real build/runtime identity, never the reference's timers, mock totals, fake publication flag or fake same-binary proof. Handle unchanged content, failed page load, failed request and retry. Technical tools remain accessible outside the main demo, with reliability/security/cancel coverage retained. Test responsive layout, accessible semantics and reduced motion including real WKWebView/safe areas.

## Authority and non-goals

Scoped source/tests, local commits and reviewed private delivery are authorized in later execution cards. No public deployment, cloud, devices, secrets/auth, finances, new native business capabilities, universal UI framework, transport redesign, service autostart or deletion of historical evidence. This planning card changes docs/specs only and makes no remote writes. Final product acceptance stays owner-owned; engineering review is not a new product approval request.

## Canonical packet

- Normative English behavior: `openspec/changes/implement-explain-v2/specs/explain-demo/spec.md`.
- Engineering decisions/event and reload contract: that change's `design.md`.
- Bounded ownership, commands, routing, evidence and estimates: `EXPLAIN_V2_PLAN.md`.
- Non-production visual reference: `docs/design/explain-v2/`.

## Владельцу

Основа уже работает; остаётся превратить техническую демонстрацию в понятный интерфейс. План: сначала веб-сценарий и честное обновление, затем компактная оболочка с восстановлением после ошибки, затем проверка всей демонстрации на одном установленном приложении. Главный риск — не оформление, а корректный переход между реальными веб-сборками и проверка ошибок/компоновки в WKWebView без потери существующих тестов.

Ориентир после технического review: один рабочий день активной реализации и проверок; с исправлениями — до двух. Это оценка, не обещанный срок. Нового согласования выбранного дизайна не требуется. Итоговый кандидат будет отдельно предъявлен на продуктовую приёмку; сейчас UI ещё не реализован.
