# DELTA v0.5.50 — живой read-only аудит справочников S3

Дата: 21.09.2026

## Основание

Аудит `order/synchronize` и связанных контроллеров показал, что перед новым DRY_RUN v2 нужно получить фактические серверные значения, а не подставлять догадки.

Документация подтверждает read-only источники:
- статусов заказа и оплаты;
- типов/статусов операций;
- валют;
- платёжных служб;
- активной смены;
- сотрудников канала;
- информации об устройстве;
- налогов профиля.

## 🟢 Что делает v0.5.50

После обычной авторизации I-Retail выполняются только семантически read-only запросы:

- `reference/get-order-status`;
- `reference/get-order-statuses`;
- `reference/get-order-payment-status`;
- `reference/get-statuses-operation`;
- `reference/get-types-operation`;
- `reference/get-statuses-shift`;
- `reference/get-currencies`;
- `reference/get-types-offer`;
- `service-in/get-service-in`;
- `service-in/get-service-in-list`;
- `service-in/get-service-in-types`;
- `iretail/shift/get-current-active-shift`;
- `iretail/employee/get-by-channel`;
- `iretail/device/get-device-info`;
- `iretail/tax/get`.

Все запросы сохраняются в безопасном отчёте с удалением секретов, токенов, PIN, кодов устройства, персональных телефонов/e-mail и других чувствительных значений.

## 🔴 Что НЕ вызывается

- `iretail/order/synchronize`;
- любые create/edit/cancel/update заказа;
- `device/register`;
- `shift/open-shift`;
- `shift/close-shift`;
- `employee/authorize`;
- `payment-in/create`;
- фискализация;
- платёжные операции.

## Цель

Получить доказанные:
- ID статусов заказа/оплаты;
- реальные service_in slug;
- активный shift_id/check_counter/cashier_opening_id;
- безопасные идентификаторы сотрудников канала;
- безопасные сведения об устройстве;
- VAT/tax данные профиля;
- справочник валют и типов товаров.

После этого строится новый локальный `DRY_RUN v2` без сетевой отправки заказа.
