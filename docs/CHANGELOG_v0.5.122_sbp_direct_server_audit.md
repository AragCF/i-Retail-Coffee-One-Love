# CHANGELOG v0.5.122 — прямой СБП на JL22 без Kozen

Дата: 25.09.2026.

## Исправление архитектурной трактовки

Предыдущий dual-mode контракт ошибочно связывал экранный QR на JL22 с источником QR в SmartSkyPOS/Kozen.

Подтверждённое требование иное:

- СБП через Kozen — отдельный платёжный контур;
- СБП через QR на экране JL22 — отдельный платёжный контур, который обязан работать без Kozen.

## Документальные основания

### Старый TSO

`docs/TSO_REFERENCE_NOTES_v0.4.md` фиксирует:

- `iretail/channel/get-available-services-in`;
- `iretail/order/create-payment-for-order`;
- `order/get-by-id`.

### Старый pay-methods.xml

Есть отдельный включённый:

`id=7777 slug=payin_payout currency=RUB title=Online enabled=true`.

Он отделён от `external_plastic_cards`.

### Актуальный backend

Ранее доказаны:

- `iretail/payment-in/create`;
- service-in slugs `sbp`, `sbp_low_risk`;
- но текущий profile 2512 как used возвращал только `external` и `external_plastic_cards`.

Следовательно, прямой СБП технически опирается на серверный online/PayIn-PayOut слой, но точный текущий create/status контракт и активную службу нужно подтвердить.

## Изменения

- создан `docs/SBP_DUAL_MODE_CONTRACT_v2.0.0.md`;
- v1.0.0 помечен как устаревший;
- в Kotlin-контракт добавлен независимый `SbpPaymentSource`:
  - `KOZEN_SMARTSKY`;
  - `DIRECT_SERVER`;
- сохранён отдельный `SbpPresentationMode`;
- создан `docs/SBP_DIRECT_SERVER_EVIDENCE_v0.5.122.md`;
- создан `tools/iRetailDirectSbpReadonlyAudit.ps1`;
- создан `MAIN_37_SBP_DIRECT_SERVER_READONLY_AUDIT.bat`;
- добавлен CI guard, запрещающий зависимость direct-аудита от ADB/Kozen/SmartSky.

## Сетевые действия текущей версии

Разрешены только:

- GET актуальной публичной apiDoc;
- i-Retail authentication;
- read-only service-in metadata;
- read-only channel metadata.

Не выполняются:

- `iretail/order/create-payment-for-order`;
- `iretail/payment-in/create`;
- `order/create`;
- `order/pay`;
- `iretail/order/synchronize`.

## Следующий этап

По отчёту `MAIN_37` определить:

- точный create endpoint;
- QR URL/payload response;
- server payment id;
- TTL;
- status endpoint;
- финальные статусы;
- актуальный service-in для текущего профиля/канала.

После этого реализовать отдельный `DirectSbpPaymentClient`, не имеющий зависимостей от Kozen.
