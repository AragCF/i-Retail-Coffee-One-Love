# CHANGELOG v0.5.124 — инвентаризация каналов для прямого СБП

Дата: 25.09.2026.

## Основание

Автоматически опубликованный `SBP_DIRECT_SERVICES_20260925_171642.zip` доказал:

- `sbp` и `sbp_low_risk` существуют в глобальном service-in справочнике;
- для configured channel 5676 оба отсутствуют среди доступных служб;
- `service-in/get-used(profile_id=2512)` также не содержит SBP;
- `get-available-services-in` вернул `user_verified=true`, `shop_verified=false`;
- доступные channel 5676 службы: `external`, `external_plastic_cards`, `payme_alfa`, `goswiff`;
- актуальный серверный direct-payment контракт подтверждён:
  `payment-in/create`, `payment-in/get-status`, `order/get-payment-data` с `payment_link` / `qr_code`.

## Что добавлено

`tools/iRetailSbpChannelInventory.ps1`

Read-only перебирает все каналы текущего профиля и для каждого получает:

- channel id/name/type/status;
- `channel.enable`;
- `related.enabled`;
- наличие offline PayIn-PayOut shop;
- `user_verified`;
- `shop_verified`;
- доступные payment services;
- список `sbp*` services.

`MAIN_39_SBP_CHANNEL_INVENTORY.bat`

Запускает аудит и автоматически публикует ZIP+SHA256 в текущую Git-ветку.

`tools/analyze_sbp_channel_inventory_report.py`

Автоматически разбирает опубликованный ZIP в CI, чтобы ChatGPT мог продолжить работу непосредственно из Git.

## Безопасность

Не выполняются:

- создание/изменение channel;
- payment-in/create;
- payment-in/revert;
- order create/pay;
- Kozen/SmartSkyPOS/AOA/ADB операции.

## Цель

Различить два сценария:

1. в профиле уже есть иной верифицированный канал с SBP — тогда проверяем его применимость;
2. ни один канал профиля не имеет SBP — тогда текущий блокер однозначно серверная настройка/верификация PayIn-PayOut, а не Android.
