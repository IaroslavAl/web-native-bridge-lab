import type { LoadedDemo } from "./demoState";
import type { Connection, DemoAction, Operation } from "./demoTypes";
import type { LabVariant, WebIdentity } from "./webIdentity";

export function displayIdentity(identity: WebIdentity | null, variant: LabVariant): string {
  if (!identity) return `Веб ${variant} · версия веб-сборки недоступна`;
  const basename = identity.entryPath.split("/").pop();
  return `Веб ${identity.variant} · ${basename}`;
}

export function initialCopy(loaded: LoadedDemo): string {
  if (loaded.update === "unchanged") return "Загружен прежний веб-экран";
  if (loaded.update === "changed-a") return "Веб-экран обновлён; расчёт пока недоступен";
  if (loaded.update === "changed-to-b") return "Раньше вы получили каталог. Теперь веб-экран умеет рассчитать заказ";
  if (loaded.capability === "quote") return "Этот экран умеет рассчитать заказ из двух блокнотов";
  return "Сначала запросим настоящий каталог через установленное приложение";
}

export function actionLabel(action: DemoAction, operation: Operation, loaded: LoadedDemo): string {
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

export function routeState(connection: Connection, operation: Operation) {
  if (connection === "error") {
    return { direction: "neutral", text: "Связь с приложением недоступна. Запрос к серверу не отправлен" } as const;
  }
  if (operation.kind === "pending" && operation.action !== "reload") {
    return { direction: "forward", text: "Ждём ответ через приложение" } as const;
  }
  if (operation.kind === "result") {
    return { direction: "back", text: "Ответ получен. Экран показывает результат" } as const;
  }
  if (operation.kind === "error" && operation.error.responseReceived) {
    return { direction: "back", text: "Ответ получен, но успешного результата нет" } as const;
  }
  if (operation.kind === "pending" && operation.action === "reload") {
    return { direction: "neutral", text: "Загружаем веб-экран. Запрос к серверу не отправляется" } as const;
  }
  return { direction: "neutral", text: "Экран задаёт действие; приложение передаёт запрос" } as const;
}
