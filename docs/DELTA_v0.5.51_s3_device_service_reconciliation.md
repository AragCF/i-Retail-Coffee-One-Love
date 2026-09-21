# DELTA v0.5.51 — read-only сверка устройства и платёжных служб S3

Дата: 21.09.2026

## Основание

Живой аудит v0.5.50 подтвердил статусы, валюту, тип товара, налог и сотрудника канала, но выявил два оставшихся блокера:

1. configured `device_id=6287` возвращает `error.cashboxNotFind` для:
   - `iretail/device/get-device-info`;
   - `iretail/shift/get-current-active-shift`.

2. `service-in/get-service-in` фактически требует `profile_id`, хотя старая опубликованная страница apiDoc этого не указала.

## Цель

Только чтением получить фактические устройства канала и фактически настроенные платёжные службы профиля.

## 🟢 Read-only запросы

- `iretail/channel/get` с текущим channel_id;
- `iretail/device/get-by-channel-id` с текущим channel_id;
- для каждого найденного устройства, не более 20:
  - `iretail/device/get-device-info`;
  - `iretail/shift/get-current-active-shift`;
- `service-in/get-service-in` с profile_id;
- `service-in/get-used` с profile_id;
- `service-in/get-service-in-types`.

## Что фиксируется

Безопасный отчёт должен показать:
- список найденных device ID;
- присутствует ли configured device_id среди устройств канала;
- для каждого устройства:
  - доступен ли device-info;
  - есть ли активная смена;
  - shift_id;
  - shift status;
  - check_counter;
  - cashier_opening_id;
- доступные/использованные service_in ID и slug;
- безопасные характеристики канала.

## 🔴 Не вызывается

- `device/register`;
- `device/register-external-system`;
- `shift/open-shift`;
- `shift/close-shift`;
- `employee/authorize`;
- `payment-in/create`;
- `order/synchronize`;
- любые create/edit/cancel/update заказа.

## Безопасность

- access token, password, client_secret не сохраняются;
- device_code/external_code/PIN не сохраняются;
- имена, телефоны, e-mail и адреса редактируются;
- сырые ответы остаются только во временном каталоге и удаляются;
- при неоднозначности устройство автоматически не выбирается.

## Следующий шаг

Если найден единственный доказанный кассовый device ID с рабочей активной сменой — использовать его только в DRY_RUN v2.

Если устройств несколько или активной смены нет — зафиксировать blocker и не выполнять order/synchronize.
