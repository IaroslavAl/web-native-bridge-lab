import { fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { App, describeDemoError } from "./App";
import { BridgeClient, BridgeClientError, TransportError } from "./bridgeClient";
import { ResponseInterpretationError } from "./scenarios";
import { MockNativeBoundary } from "./test/MockNativeBoundary";
import type { StoragePort, WebIdentity } from "./webIdentity";

const session = "0123456789abcdef0123456789abcdef";
const aIdentity: WebIdentity = { variant: "A", entryPath: "/assets/index-a.js" };
const bIdentity: WebIdentity = { variant: "B", entryPath: "/assets/index-b.js" };

function clientFor(handler: (message: Record<string, unknown>) => unknown): { client: BridgeClient; native: MockNativeBoundary } {
  const native = new MockNativeBoundary((message) =>
    message.type === "hello" ? { v: 1, type: "helloAck", session } : handler(message),
  );
  return { client: new BridgeClient(native), native };
}

function storageWith(raw: string | null = null): StoragePort & { current(): string | null } {
  let value = raw;
  return {
    getItem: () => value,
    setItem: (_key, next) => { value = next; },
    removeItem: () => { value = null; },
    current: () => value,
  };
}

async function readyButton(name: string | RegExp) {
  const button = await screen.findByRole("button", { name });
  await vi.waitFor(() => expect(button).toBeEnabled());
  return button;
}

describe("Explain demo with an explicitly mocked native boundary", () => {
  it("shows the focused Russian A journey with one action and no engineering controls", async () => {
    const { client } = clientFor(() => { throw new Error("No request expected"); });
    render(<App createClient={() => client} variant="A" identity={aIdentity} storage={storageWith()} />);

    expect(screen.getByRole("heading", { name: "Как это работает" })).toBeVisible();
    const route = screen.getByLabelText("Путь запроса и ответа");
    expect(route).toHaveTextContent("Экран");
    expect(route).toHaveTextContent("Приложение");
    expect(route).toHaveTextContent("Сервер");
    expect(await readyButton("Получить каталог")).toBeVisible();
    expect(screen.getByText("Экран отправляет запрос через приложение и показывает ответ сервера.")).toBeVisible();
    expect(route).toHaveTextContent("передаёт запрос");
    expect(screen.queryByText(/HTTP|непрозрачн/i)).not.toBeInTheDocument();
    expect(screen.queryByText("Diagnostics")).not.toBeInTheDocument();
    expect(screen.queryByLabelText("Scenario")).not.toBeInTheDocument();
    expect(screen.getAllByRole("button")).toHaveLength(1);
  });

  it("renders actual returned catalog data and never renames an unknown item", async () => {
    const { client, native } = clientFor((message) => ({
      v: 1, type: "response", id: message.id, status: 200, headers: {},
      body: '{"items":[{"sku":"marker","title":"Green marker"}],"total":1}',
    }));
    render(<App createClient={() => client} variant="A" identity={aIdentity} storage={storageWith()} />);

    await userEvent.click(await readyButton("Получить каталог"));

    expect(await screen.findByText("Green marker")).toBeVisible();
    expect(screen.getByText("marker")).toBeVisible();
    expect(screen.queryByText("Блокнот", { exact: true })).not.toBeInTheDocument();
    expect(native.decodedMessages()[1]).toMatchObject({ method: "GET", url: expect.stringContaining("category=books") });
    expect(screen.getByRole("button", { name: "Загрузить обновлённый экран" })).toBeVisible();
  });

  it.each([
    ["USD", 1357, /13,57/],
    ["EUR", 2468, /24,68/],
    ["JPY", 1201, /1\s201/],
    ["KWD", 1201, /1,201/],
  ])("renders returned %s quote using its minor-unit exponent", async (currency, totalMinor, displayedAmount) => {
    const { client } = clientFor((message) => ({
      v: 1, type: "response", id: message.id, status: 200, headers: {},
      body: JSON.stringify({ quote: { sku: "notebook", quantity: 3, totalMinor, currency } }),
    }));
    const history = JSON.stringify({ v: 1, previous: aIdentity, catalogSeen: true, updateRequested: true });
    render(<App createClient={() => client} variant="B" identity={bIdentity} storage={storageWith(history)} />);

    await userEvent.click(await readyButton("Рассчитать заказ"));

    expect(await screen.findByText(/3\s+штуки/)).toBeVisible();
    const total = screen.getByTestId("demo.quote-total");
    expect(total).toHaveTextContent(displayedAmount);
    expect(total).toHaveAttribute("data-currency", currency);
    expect(total).toHaveAttribute("data-total-minor", String(totalMinor));
    expect(screen.getByText("Веб-экран изменился: теперь вместо каталога он умеет рассчитать заказ. Оба действия проходят через уже доступную связь приложения с сервером.")).toBeVisible();
    expect(screen.queryByText(/HTTP|идентичност/i)).not.toBeInTheDocument();
  });

  it("rejects an unsupported currency without leaving a receipt and keeps retry usable", async () => {
    const { client } = clientFor((message) => ({
      v: 1, type: "response", id: message.id, status: 200, headers: {},
      body: '{"quote":{"sku":"notebook","quantity":2,"totalMinor":1200,"currency":"ZZZ"}}',
    }));
    render(<App createClient={() => client} variant="B" identity={bIdentity} storage={storageWith()} />);

    await userEvent.click(await readyButton("Рассчитать заказ"));

    expect(await screen.findByRole("alert")).toHaveTextContent("Ответ получен, но экран не смог проверить данные");
    expect(screen.queryByTestId("demo.quote-total")).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Повторить расчёт" })).toBeEnabled();
    expect(screen.getByLabelText("Путь запроса и ответа")).toHaveAttribute("data-direction", "back");
  });

  it("keeps reverse response direction for a correlated HTTP 503", async () => {
    const { client } = clientFor((message) => ({
      v: 1, type: "response", id: message.id, status: 503, headers: {}, body: '{"error":"unavailable"}',
    }));
    render(<App createClient={() => client} variant="B" identity={bIdentity} storage={storageWith()} />);

    await userEvent.click(await readyButton("Рассчитать заказ"));

    expect(await screen.findByRole("alert")).toHaveTextContent("Сервер вернул ошибку HTTP 503");
    expect(screen.queryByTestId("demo.quote-total")).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Повторить расчёт" })).toBeEnabled();
    expect(screen.getByLabelText("Путь запроса и ответа")).toHaveAttribute("data-direction", "back");
    expect(screen.getByRole("status")).toHaveTextContent("Ответ получен, но успешного результата нет");
  });

  it.each([
    ['{"error":{"code":"OUT_OF_STOCK","message":"Unavailable"}}', "Ответ получен, но действие отклонено"],
    ["{", "Ответ получен, но экран не смог прочитать данные"],
  ])("keeps reverse response direction for interpreted response failure %s", async (body, title) => {
    const { client } = clientFor((message) => ({
      v: 1, type: "response", id: message.id, status: 200, headers: {}, body,
    }));
    render(<App createClient={() => client} variant="B" identity={bIdentity} storage={storageWith()} />);

    await userEvent.click(await readyButton("Рассчитать заказ"));

    expect(await screen.findByRole("alert")).toHaveTextContent(title);
    expect(screen.getByLabelText("Путь запроса и ответа")).toHaveAttribute("data-direction", "back");
    expect(screen.queryByTestId("demo.quote-total")).not.toBeInTheDocument();
  });

  it.each([-1, 1.5])("shows an interpretation error instead of a receipt for malformed totalMinor %s", async (totalMinor) => {
    const { client } = clientFor((message) => ({
      v: 1, type: "response", id: message.id, status: 200, headers: {},
      body: JSON.stringify({ quote: { sku: "notebook", quantity: 2, totalMinor, currency: "USD" } }),
    }));
    render(<App createClient={() => client} variant="B" identity={bIdentity} storage={storageWith()} />);

    await userEvent.click(await readyButton("Рассчитать заказ"));

    expect(await screen.findByRole("alert")).toHaveTextContent("Ответ получен, но экран не смог проверить данные");
    expect(screen.queryByTestId("demo.quote-total")).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Повторить расчёт" })).toBeVisible();
    expect(screen.getByLabelText("Путь запроса и ответа")).toHaveAttribute("data-direction", "back");
  });

  it("excludes duplicate activation synchronously and shows actual pending state", async () => {
    let resolveRequest: ((value: unknown) => void) | undefined;
    const { client, native } = clientFor((message) => new Promise((resolve) => {
      resolveRequest = resolve;
    }));
    render(<App createClient={() => client} variant="A" identity={aIdentity} storage={storageWith()} />);
    const button = await readyButton("Получить каталог");

    fireEvent.click(button);
    fireEvent.click(button);

    expect(screen.getByRole("status")).toHaveTextContent("Ждём ответ через приложение");
    await vi.waitFor(() => {
      expect(native.decodedMessages().filter((message) => message.type === "request")).toHaveLength(1);
    });
    resolveRequest?.({ v: 1, type: "response", id: 1, status: 200, headers: {}, body: '{"items":[],"total":0}' });
    expect(await screen.findByText("В каталоге нет товаров")).toBeVisible();
  });

  it("does not repaint a detached document after a late completion", async () => {
    let resolveRequest: ((value: unknown) => void) | undefined;
    const { client } = clientFor(() => new Promise((resolve) => { resolveRequest = resolve; }));
    const view = render(<App createClient={() => client} variant="A" identity={aIdentity} storage={storageWith()} />);
    await userEvent.click(await readyButton("Получить каталог"));
    view.unmount();

    resolveRequest?.({ v: 1, type: "response", id: 1, status: 200, headers: {}, body: '{"items":[{"sku":"late","title":"Late"}],"total":1}' });
    await Promise.resolve();
    expect(screen.queryByText("Late")).not.toBeInTheDocument();
  });

  it("creates a fresh client after a rejected handshake", async () => {
    const rejected = new BridgeClient(new MockNativeBoundary(() => Promise.reject(new Error("rejected"))));
    const recovered = clientFor(() => { throw new Error("No request expected"); });
    const createClient = vi.fn()
      .mockReturnValueOnce(rejected)
      .mockReturnValueOnce(recovered.client);
    render(<App createClient={createClient} variant="A" identity={aIdentity} storage={storageWith()} />);

    expect(await screen.findByRole("alert")).toHaveTextContent("Не удалось подключить веб-экран к приложению");
    expect(screen.getByLabelText("Путь запроса и ответа")).toHaveAttribute("data-direction", "neutral");
    await userEvent.click(screen.getByRole("button", { name: "Повторить подключение" }));

    expect(await readyButton("Получить каталог")).toBeEnabled();
    expect(createClient).toHaveBeenCalledTimes(2);
    expect(recovered.native.decodedMessages()).toEqual([{ v: 1, type: "hello" }]);
  });

  it("preserves observed A history through a rejected handshake and successful B retry", async () => {
    const rejected = new BridgeClient(new MockNativeBoundary(() => Promise.reject(new Error("rejected"))));
    const recovered = clientFor((message) => ({
      v: 1, type: "response", id: message.id, status: 200, headers: {},
      body: '{"quote":{"sku":"notebook","quantity":2,"totalMinor":1200,"currency":"USD"}}',
    }));
    const createClient = vi.fn()
      .mockReturnValueOnce(rejected)
      .mockReturnValueOnce(recovered.client);
    const history = JSON.stringify({ v: 1, previous: aIdentity, catalogSeen: true, updateRequested: true });
    const storage = storageWith(history);
    render(<App createClient={createClient} variant="B" identity={bIdentity} storage={storage} />);

    expect(await screen.findByRole("alert")).toHaveTextContent("Не удалось подключить веб-экран к приложению");
    expect(screen.getByText("Раньше вы получили каталог. Теперь веб-экран умеет рассчитать заказ")).toBeVisible();
    expect(storage.current()).toBeNull();
    await userEvent.click(screen.getByRole("button", { name: "Повторить подключение" }));
    await userEvent.click(await readyButton("Рассчитать заказ"));

    expect(await screen.findByTestId("demo.quote-total")).toHaveTextContent(/12,00/);
    expect(screen.getByText("Веб-экран изменился: теперь вместо каталога он умеет рассчитать заказ. Оба действия проходят через уже доступную связь приложения с сервером.")).toBeVisible();
    expect(createClient).toHaveBeenCalledTimes(2);
  });

  it("persists current A identity before a real document reload", async () => {
    const { client } = clientFor((message) => ({
      v: 1, type: "response", id: message.id, status: 200, headers: {},
      body: '{"items":[{"sku":"notebook","title":"Notebook"}],"total":1}',
    }));
    const storage = storageWith();
    const reload = vi.fn();
    render(<App createClient={() => client} variant="A" identity={aIdentity} storage={storage} reload={reload} />);
    await userEvent.click(await readyButton("Получить каталог"));
    await userEvent.click(await screen.findByRole("button", { name: "Загрузить обновлённый экран" }));

    expect(screen.getByRole("button", { name: "Загружаем веб-экран…" })).toBeDisabled();
    expect(screen.getByRole("status")).toHaveTextContent("Загружаем веб-экран. Запрос к серверу не отправляется");
    expect(screen.getByRole("status")).not.toHaveTextContent("Успешный результат");
    expect(screen.queryByRole("button", { name: "Ждём ответ…" })).not.toBeInTheDocument();
    expect(JSON.parse(storage.current() ?? "null")).toMatchObject({ previous: aIdentity, catalogSeen: true, updateRequested: true });
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it("reports unchanged A only after consuming a real reload record", async () => {
    const raw = JSON.stringify({ v: 1, previous: aIdentity, catalogSeen: true, updateRequested: true });
    const { client } = clientFor(() => { throw new Error("No request expected"); });
    render(<App createClient={() => client} variant="A" identity={aIdentity} storage={storageWith(raw)} />);

    expect(await screen.findByText("Загружен прежний веб-экран")).toBeVisible();
    expect(screen.getByRole("button", { name: "Проверить обновление ещё раз" })).toBeVisible();
    expect(screen.queryByText(/не опубликован/i)).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Рассчитать заказ" })).not.toBeInTheDocument();
  });

  it("keeps changed A catalog-only and does not invent A history on cold B", async () => {
    const raw = JSON.stringify({ v: 1, previous: aIdentity, catalogSeen: true, updateRequested: true });
    const changedA = clientFor(() => { throw new Error("No request expected"); });
    const first = render(<App createClient={() => changedA.client} variant="A" identity={{ ...aIdentity, entryPath: "/assets/index-a2.js" }} storage={storageWith(raw)} />);
    expect(await screen.findByText("Веб-экран обновлён; расчёт пока недоступен")).toBeVisible();
    expect(screen.queryByRole("button", { name: "Рассчитать заказ" })).not.toBeInTheDocument();
    first.unmount();

    const coldB = clientFor(() => { throw new Error("No request expected"); });
    render(<App createClient={() => coldB.client} variant="B" identity={bIdentity} storage={storageWith()} />);
    expect(await readyButton("Рассчитать заказ")).toBeVisible();
    expect(screen.getByText("Этот экран умеет рассчитать заказ из двух блокнотов")).toBeVisible();
    expect(screen.queryByText(/раньше.*каталог/i)).not.toBeInTheDocument();
  });

  it("maps response, transport and bridge failures to distinct truthful Russian categories", () => {
    expect(describeDemoError(new ResponseInterpretationError("HTTP", "HTTP 503: body", 503))).toMatchObject({
      title: "Сервер вернул ошибку HTTP 503", responseReceived: true,
    });
    expect(describeDemoError(new ResponseInterpretationError("business", "OUT_OF_STOCK"))).toMatchObject({
      title: "Ответ получен, но действие отклонено", responseReceived: true,
    });
    expect(describeDemoError(new ResponseInterpretationError("JSON parse", "bad"))).toMatchObject({
      title: "Ответ получен, но экран не смог прочитать данные", responseReceived: true,
    });
    expect(describeDemoError(new TransportError("TIMEOUT", "late", 1))).toMatchObject({
      title: "Время ожидания ответа истекло", responseReceived: false,
    });
    expect(describeDemoError(new TransportError("CANCELLED", "cancel", 1))).toMatchObject({
      title: "Запрос отменён", responseReceived: false,
    });
    expect(describeDemoError(new TransportError("NETWORK_ERROR", "offline", 1))).toMatchObject({
      title: "Не удалось связаться с сервером", responseReceived: false,
    });
    expect(describeDemoError(new TransportError("URL_DENIED", "denied", 1))).toMatchObject({
      title: "Приложение отклонило запрос", responseReceived: false,
    });
    expect(describeDemoError(new BridgeClientError("BRIDGE_UNAVAILABLE", "missing"))).toMatchObject({
      title: "Связь с приложением недоступна", responseReceived: false,
    });
    expect(describeDemoError(new BridgeClientError("PROTOCOL_ERROR", "bad"))).toMatchObject({
      title: "Приложение вернуло непонятный ответ", responseReceived: false,
    });
    expect(describeDemoError(new Error("unknown"))).toMatchObject({
      title: "Не удалось выполнить действие", responseReceived: false,
    });
  });
});
