# CHANGELOG v0.5.52 — исправление формирования SUMMARY в Windows PowerShell

Дата: 21.09.2026

## Причина выпуска

Первый живой запуск v0.5.51 успешно дошёл до чтения серверных данных, но упал уже при локальном формировании `SUMMARY`:

`Argument types do not match`

Точка отказа: строка с `[ordered]@{ ... }`, где значения `profile_services` и `used_services` строились через `@($genericList)`.

## Причина

Windows PowerShell 5.1 имеет проблемный случай связывания `System.Collections.Generic.List[object]` внутри array-subexpression `@(...)` при формировании сложных структур.

Это локальная ошибка сценария. Серверный API здесь не виноват.

## 🟢 Исправлено

- `profileServiceItems` и `usedServiceItems` перед SUMMARY явно преобразуются через `.ToArray()`;
- SUMMARY использует только обычные массивы;
- консольное резюме также использует уже преобразованные массивы;
- добавлены автоматические проверки, запрещающие возврат паттерна:
  - `profile_services=@($profileServiceItems)`;
  - `used_services=@($usedServiceItems)`;
- версия поднята до `0.5.52-s3-device-service-summary-fix`.

## 🔴 Не изменено

- набор API-запросов;
- read-only характер проверки;
- запрет `device/register`;
- запрет открытия/закрытия смены;
- запрет `employee/authorize`;
- запрет `payment-in/create`;
- запрет `order/synchronize`;
- автоматический выбор устройства по-прежнему запрещён.

## Следующий шаг

Повторить `S3_08_RECONCILE_DEVICE_SERVICE.bat`.

Повтор безопасен: все запросы этапа являются read-only.
