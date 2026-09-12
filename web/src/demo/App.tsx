import { useEffect, useRef, useState } from "react";
import { BridgeClient } from "../bridge/BridgeClient";
import { BridgeClientError } from "../bridge/protocol";
import { classifyLoadedDemo } from "./demoState";
import type { Connection, DemoAction, DemoError, Operation } from "./demoTypes";
import { describeDemoError } from "./errorPresentation";
import { formatMinorUnits } from "./money";
import { buildCatalogRequest, buildQuoteRequest } from "./requestDefinitions";
import {
  interpretCatalog,
  interpretQuote,
} from "./responseInterpreters";
import { actionLabel, displayIdentity, initialCopy, routeState } from "./screenText";
import {
  consumeDemoHistory,
  saveUpdateHistory,
  type LabVariant,
  type StoragePort,
  type WebIdentity,
} from "./webIdentity";

interface AppProps {
  createClient: () => BridgeClient;
  variant: LabVariant;
  identity: WebIdentity | null;
  storage?: StoragePort;
  reload?: () => void;
}

export function App({ createClient, variant, identity, storage, reload }: AppProps) {
  const [connection, setConnection] = useState<Connection>("connecting");
  const [connectionError, setConnectionError] = useState<DemoError>();
  const [loaded, setLoaded] = useState(() => classifyLoadedDemo(identity, null, variant));
  const [operation, setOperation] = useState<Operation>({ kind: "idle" });
  const client = useRef<BridgeClient>();
  const detach = useRef<() => void>();
  const generation = useRef(0);
  const mounted = useRef(false);
  const busy = useRef(false);
  const continuityConsumed = useRef(false);

  function continuityStorage(): StoragePort | null {
    if (storage) return storage;
    try { return window.sessionStorage; } catch { return null; }
  }

  async function connectFresh() {
    const currentGeneration = ++generation.current;
    busy.current = false;
    detach.current?.();
    setConnection("connecting");
    setConnectionError(undefined);
    let nextClient: BridgeClient;
    try {
      nextClient = createClient();
      client.current = nextClient;
      detach.current = nextClient.attachPageLifecycle(window);
      await nextClient.connect();
      if (!mounted.current || generation.current !== currentGeneration) return;
      setConnection("ready");
    } catch (error) {
      if (!mounted.current || generation.current !== currentGeneration) return;
      client.current = undefined;
      setConnection("error");
      setConnectionError(
        error instanceof BridgeClientError
          ? describeDemoError(error)
          : {
              title: "Не удалось подключить веб-экран к приложению",
              detail: "Новый запрос к серверу не отправлялся. Повторите подключение.",
              responseReceived: false,
            },
      );
    }
    if (!mounted.current || generation.current !== currentGeneration) return;
    if (!continuityConsumed.current) {
      continuityConsumed.current = true;
      const targetStorage = continuityStorage();
      const history = targetStorage ? consumeDemoHistory(targetStorage) : null;
      setLoaded(classifyLoadedDemo(identity, history, variant));
    }
  }

  useEffect(() => {
    mounted.current = true;
    void connectFresh();
    return () => {
      mounted.current = false;
      generation.current += 1;
      detach.current?.();
    };
  }, []);

  let action: DemoAction = loaded.capability;
  if (operation.kind === "pending" || operation.kind === "error") action = operation.action;
  else if (operation.kind === "result" && operation.action === "catalog") action = "reload";
  else if (loaded.capability === "catalog" && loaded.update !== "none" && operation.kind === "idle") action = "reload";

  function runAction() {
    if (busy.current || connection !== "ready" || !client.current) return;
    if (action === "reload") {
      busy.current = true;
      setOperation({ kind: "pending", action: "reload" });
      const targetStorage = continuityStorage();
      const catalogSeen = loaded.observedCatalog
        || (operation.kind === "result" && operation.action === "catalog");
      if (identity && targetStorage) saveUpdateHistory(targetStorage, identity, catalogSeen);
      (reload ?? (() => window.location.reload()))();
      return;
    }

    busy.current = true;
    const requestGeneration = generation.current;
    setOperation({ kind: "pending", action });
    let pending;
    try {
      pending = action === "catalog"
        ? client.current.request(buildCatalogRequest("books"))
        : client.current.request(buildQuoteRequest("notebook", 2));
    } catch (error) {
      busy.current = false;
      setOperation({ kind: "error", action, error: describeDemoError(error) });
      return;
    }
    void pending.promise
      .then((response) => action === "catalog" ? interpretCatalog(response) : interpretQuote(response))
      .then((result) => {
        if (mounted.current && generation.current === requestGeneration) {
          setOperation({ kind: "result", action, result });
        }
      })
      .catch((error: unknown) => {
        if (mounted.current && generation.current === requestGeneration) {
          setOperation({ kind: "error", action, error: describeDemoError(error) });
        }
      })
      .finally(() => {
        if (mounted.current && generation.current === requestGeneration) busy.current = false;
      });
  }

  const route = routeState(connection, operation);
  const isPending = operation.kind === "pending";
  const currentResult = operation.kind === "result" ? operation.result : null;
  const currentError = operation.kind === "error" ? operation.error : connectionError;

  return (
    <main className="explain-shell">
      <header className="explain-header">
        <p className="eyebrow">Веб · приложение · сервер</p>
        <h1>Как это работает</h1>
        <p className="intro-copy">Экран отправляет запрос через приложение и показывает ответ сервера.</p>
        <p className="web-identity" data-testid="lab.variant">{displayIdentity(identity, variant)}</p>
      </header>

      <section className="journey" aria-label="Путь запроса и ответа" data-direction={route.direction}>
        <ol className="route">
          <li><span aria-hidden="true">▣</span><strong>Экран</strong><small>задаёт действие</small></li>
          <li className="route-arrow" aria-hidden="true">→</li>
          <li><span aria-hidden="true">▤</span><strong>Приложение</strong><small>передаёт запрос</small></li>
          <li className="route-arrow" aria-hidden="true">→</li>
          <li><span aria-hidden="true">▰</span><strong>Сервер</strong><small>возвращает ответ</small></li>
        </ol>
        <p className="route-note">Схема обмена; точный этап сервера не виден.</p>
      </section>

      <section className="outcome" aria-labelledby="outcome-title">
        <p className="phase">{loaded.capability === "catalog" ? "Каталог" : "Расчёт заказа"}</p>
        <h2 id="outcome-title">{initialCopy(loaded)}</h2>

        <div className="current" role="status" aria-live="polite">
          <strong>{connection === "connecting" ? "Подключаемся к приложению" : route.text}</strong>
          {connection === "connecting" && <p>Запрос к серверу ещё не отправлен.</p>}
          {isPending && action !== "reload" && <p>Успешный результат появится только после проверки ответа веб-экраном.</p>}
        </div>

        {currentResult?.kind === "catalog" && (
          <div className="result-card" data-testid="demo.catalog-result">
            <strong>Ответ каталога</strong>
            {currentResult.items.length === 0
              ? <p>В каталоге нет товаров</p>
              : currentResult.items.map((item) => <p key={item.sku}><b>{item.title}</b><span>{item.sku}</span></p>)}
            <small>Всего в ответе: {currentResult.total}</small>
            <p className="presenter-note">Ведущий отдельно заменяет готовые веб-файлы. Кнопка ниже только перезагружает этот экран.</p>
          </div>
        )}

        {currentResult?.kind === "quote" && (
          <div className="result-card receipt">
            <strong>Расчёт получен</strong>
            <p><b>{currentResult.quote.sku === "notebook" ? "Блокнот" : currentResult.quote.sku}</b><span>{currentResult.quote.quantity} штуки · {currentResult.quote.sku}</span></p>
            <p className="total"><span>Итого</span><b data-testid="demo.quote-total"
              data-currency={currentResult.quote.currency}
              data-total-minor={currentResult.quote.totalMinor}>
              {formatMinorUnits(
                currentResult.quote.totalMinor,
                currentResult.quote.currency,
                currentResult.quote.minorUnitExponent,
              )}
            </b></p>
            {loaded.observedCatalog && <p className="comparison">Веб-экран изменился: теперь вместо каталога он умеет рассчитать заказ. Оба действия проходят через уже доступную связь приложения с сервером.</p>}
          </div>
        )}

        {currentError && <div className="error-card" role="alert"><strong>{currentError.title}</strong><p>{currentError.detail}</p></div>}

        {connection === "error" ? (
          <button className="primary" onClick={() => void connectFresh()}>Повторить подключение</button>
        ) : (
          <button className={currentResult?.kind === "quote" ? "secondary" : "primary"}
            onClick={runAction} disabled={connection !== "ready" || isPending}>
            {actionLabel(action, operation, loaded)}
          </button>
        )}
      </section>
    </main>
  );
}
