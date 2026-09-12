import { BridgeClientError, TransportError } from "../bridge/protocol";
import { ResponseInterpretationError } from "./responseInterpreters";
import type { DemoError } from "./demoTypes";

function assertNever(value: never): never {
  throw new Error(`Unhandled interpretation category: ${String(value)}`);
}

export function describeDemoError(error: unknown): DemoError {
  if (error instanceof ResponseInterpretationError) {
    const category = error.category;
    switch (category) {
      case "HTTP":
        return {
          title: `Сервер вернул ошибку HTTP${error.status ? ` ${error.status}` : ""}`,
          detail: "Ответ получен, но успешного результата в нём нет.",
          responseReceived: true,
        };
      case "business":
        return {
          title: "Ответ получен, но действие отклонено",
          detail: "Сервер объяснил, что действие нельзя завершить. Можно повторить запрос.",
          responseReceived: true,
        };
      case "invalid success shape":
        return {
          title: "Ответ получен, но экран не смог проверить данные",
          detail: "Формат результата отличается от ожидаемого. Повторите запрос.",
          responseReceived: true,
        };
      case "JSON parse":
        return {
          title: "Ответ получен, но экран не смог прочитать данные",
          detail: "Содержимое ответа не является корректным JSON. Повторите запрос.",
          responseReceived: true,
        };
    }
    return assertNever(category);
  }
  if (error instanceof TransportError) {
    if (error.code === "TIMEOUT") return { title: "Время ожидания ответа истекло", detail: "Приложение остановило запрос по тайм-ауту. Можно повторить.", responseReceived: false };
    if (error.code === "CANCELLED") return { title: "Запрос отменён", detail: "Успешного результата нет. Можно повторить запрос.", responseReceived: false };
    if (error.code === "NETWORK_ERROR") return { title: "Не удалось связаться с сервером", detail: "Приложение не получило сетевой ответ. Проверьте сервис и повторите.", responseReceived: false };
    return { title: "Приложение отклонило запрос", detail: `Категория транспорта: ${error.code}. Можно повторить.`, responseReceived: false };
  }
  if (error instanceof BridgeClientError) {
    return error.category === "bridge"
      ? { title: "Связь с приложением недоступна", detail: "Откройте экран внутри Bridge Lab и повторите подключение.", responseReceived: false }
      : { title: "Приложение вернуло непонятный ответ", detail: "Защищённый формат ответа не прошёл проверку. Повторите подключение.", responseReceived: false };
  }
  return { title: "Не удалось выполнить действие", detail: "Произошла непредвиденная ошибка. Повторите попытку.", responseReceived: false };
}
