import { useEffect, useRef, useState } from "react";
import {
  BridgeClient,
  BridgeClientError,
  TransportError,
} from "./bridgeClient";
import { classifyLoadedDemo, type LoadedDemo } from "./demoState";
import { formatMinorUnits } from "./money";
import {
  ResponseInterpretationError,
  buildCatalogRequest,
  buildQuoteRequest,
  interpretCatalog,
  interpretQuote,
  type ScenarioResult,
} from "./scenarios";
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

type DemoAction = "catalog" | "quote" | "reload";
type Connection = "connecting" | "ready" | "error";
type Operation =
  | { kind: "idle" }
  | { kind: "pending"; action: DemoAction }
  | { kind: "result"; action: "catalog" | "quote"; result: ScenarioResult }
  | { kind: "error"; action: "catalog" | "quote"; error: DemoError };

export interface DemoError {
  title: string;
  detail: string;
}

export function describeDemoError(error: unknown): DemoError {
  if (error instanceof ResponseInterpretationError) {
    if (error.category === "HTTP") {
      return {
        title: `Сервер вернул ошибку HTTP${error.status ? ` ${error.status}` : ""}`,
        detail: "Ответ получен, но успешного результата в нём нет.",
      };
    }
    if (error.category === "business") {
      return error.message.startsWith("Unexpected")
        ? { title: "Ответ получен, но экран не смог проверить данные", detail: "Формат результата отличается от ожидаемого. Повторите запрос." }
        : { title: "Ответ получен, но действие отклонено", detail: "Сервер объяснил, что действие нельзя завершить. Можно повторить запрос." };
    }
    return {
      title: "Ответ получен, но экран не смог прочитать данные",
      detail: "Содержимое ответа не является корректным JSON. Повторите запрос.",
    };
  }
  if (error instanceof TransportError) {
    if (error.code === "TIMEOUT") return { title: "Время ожидания ответа истекло", detail: "Приложение остановило запрос по тайм-ауту. Можно повторить." };
    if (error.code === "CANCELLED") return { title: "Запрос отменён", detail: "Успешного результата нет. Можно повторить запрос." };
    if (error.code === "NETWORK_ERROR") return { title: "Не удалось связаться с сервером", detail: "Приложение не получило сетевой ответ. Проверьте сервис и повторите." };
    return { title: "Приложение отклонило запрос", detail: `Категория транспорта: ${error.code}. Можно повторить.` };
  }
  if (error instanceof BridgeClientError) {
    return error.category === "bridge"
      ? { title: "Связь с приложением недоступна", detail: "Откройте экран внутри Bridge Lab и повторите подключение." }
      : { title: "Приложение вернуло непонятный ответ", detail: "Защищённый формат ответа не прошёл проверку. Повторите подключение." };
  }
  return { title: "Не удалось выполнить действие", detail: "Произошла непредвиденная ошибка. Повторите попытку." };
}

function displayIdentity(identity: WebIdentity | null, variant: LabVariant): string {
  if (!identity) return `Веб ${variant} · версия веб-сборки недоступна`;
  const basename = identity.entryPath.split("/").pop();
  return `Веб ${identity.variant} · ${basename}`;
}

function initialCopy(loaded: LoadedDemo): string {
  if (loaded.update === "unchanged") return "Загружен прежний веб-экран";
  if (loaded.update === "changed-a") return "Веб-экран обновлён; расчёт пока недоступен";
  if (loaded.update === "changed-to-b") return "Раньше вы получили каталог. Теперь веб-экран умеет рассчитать заказ";
  if (loaded.capability === "quote") return "Этот экран умеет рассчитать заказ из двух блокнотов";
  return "Сначала запросим настоящий каталог через установленное приложение";
}

function actionLabel(action: DemoAction, operation: Operation, loaded: LoadedDemo): string {
  if (operation.kind === "pending") {
    return action === "reload" ? "Загружаем веб-экран…" : "Ждём ответ…";
  }
  if (operation.kind === "error") return action === "catalog" ? "Повторить запрос каталога" : "Повторить расчёт";
  if (action === "catalog") return "Получить каталог";
  if (action === "quote") return operation.kind === "result" ? "Рассчитать снова" : "Рассчитать заказ";
  return loaded.update === "unchanged" || loaded.update === "changed-a"
    ? "Проверить обновление ещё раз"
    : "Загрузить обновлённый экран";
}

function routeState(operation: Operation) {
  if (operation.kind === "pending" && operation.action !== "reload") {
    return { direction: "forward", text: "Ждём ответ через приложение" } as const;
  }
  if (operation.kind === "result") {
    return { direction: "back", text: "Ответ получен. Экран показывает результат" } as const;
  }
  if (operation.kind === "error" && operation.error.title.startsWith("Ответ получен")) {
    return { direction: "back", text: "Ответ получен, но успешного результата нет" } as const;
  }
  if (operation.kind === "pending" && operation.action === "reload") {
    return { direction: "neutral", text: "Загружаем веб-экран. Запрос к серверу не отправляется" } as const;
  }
  return { direction: "neutral", text: "Экран задаёт действие; приложение передаёт запрос" } as const;
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
      if (identity && targetStorage) saveUpdateHistory(targetStorage, identity, true);
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

  const route = routeState(operation);
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
