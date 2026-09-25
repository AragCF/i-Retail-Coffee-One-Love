# SBP DIRECT JL22 — доказательства и пробелы v0.5.122

Дата: 25.09.2026.

## Вывод

В проектной документации **есть достаточные основания строить второй СБП-контур как серверную онлайн-оплату без Kozen**.

При этом полного актуального боевого контракта create/status пока нет. Поэтому следующий шаг — read-only аудит актуального i-Retail API, а не догадки.

## 1. UI уже разделяет POS и онлайн-QR

`docs/PROTOCOL_iRetail_Android_UI_v0.2.md` отдельно определяет:

- `PAYMENT_POS` — оплата банковской картой через терминал;
- `PAYMENT_ONLINE_QR` — онлайн-оплата по QR;
- `PAYMENT_ONLINE_CONFIRM` — ожидание/подтверждение онлайн-оплаты.

Сценарий онлайн-оплаты не требует, чтобы QR был получен из POS.

## 2. Старый TSO знает серверный online-payment

`docs/TSO_REFERENCE_NOTES_v0.4.md` фиксирует найденные в старом TSO серверные команды:

- `order/reserve-order-id`;
- `order/create`;
- `order/pay`;
- `order/get-by-id`;
- `iretail/channel/get-available-services-in`;
- `iretail/order/create-payment-for-order`;
- `iretail/check/send`.

Это важнейшее свидетельство прямого серверного пути:

- сервер выдаёт доступные способы оплаты;
- сервер умеет создавать online payment для заказа;
- состояние заказа можно перечитывать отдельно.

## 3. Старый pay-methods.xml отделяет Online от внешнего эквайринга

`app/src/main/assets/content/pay-methods.xml` содержит включённый:

`id=7777 slug=payin_payout currency=RUB title=Online enabled=true`.

Отдельно присутствуют:

- `external_plastic_cards` — внешний карточный эквайринг;
- `external_plastic_nonitgerated`;
- `external` — наличные.

Следовательно, историческая модель i-Retail уже различала серверную онлайн-оплату и физический внешний POS.

## 4. Актуальная документация подтверждает PayIn-PayOut слой

`docs/S3_ORDER_DEPENDENCY_FINDINGS_v0.5.49_20260921.md` фиксирует:

- `service-in/get-service-in`;
- `service-in/get-service-in-list`;
- `service-in/get-service-in-types`;
- `iretail/payment-in/create`.

Для `iretail/payment-in/create` документированы как минимум:

- `device_id`;
- `sum`;
- `order_number`;
- `service_in_id` или `service_in_slug`;
- optional phone.

Это серверный PayIn-PayOut контур.

## 5. Актуальный сервер знает SBP services

`docs/S3_LIVE_REFERENCE_FINDINGS_v0.5.50_20260921.md` фиксирует, что живой:

`service-in/get-service-in-list`

возвращал среди прочего:

- `sbp`;
- `sbp_low_risk`;
- `external`;
- `external_plastic_cards`;
- `external_plastic_nonitgerated`;
- `goswiff`;
- `payme_alfa`;
- `i_bonus`.

Это прямое доказательство, что сущности СБП существуют в текущем i-Retail backend, а не только в Kozen/SmartSkyPOS.

## 6. Текущий профиль пока не доказан как подключённый к SBP

`docs/S3_DEVICE_SERVICE_SAFE_FINDINGS_v0.5.54_20260921.md` фиксирует:

`service-in/get-used(profile_id=2512)`

и там подтверждены только:

- `external`;
- `external_plastic_cards`.

Поэтому нельзя автоматически выбрать `sbp` или `sbp_low_risk`.

Возможные объяснения, которые надо различить фактами:

1. СБП доступен каналу, но не помечен used для профиля;
2. требуется отдельная серверная настройка;
3. нужен старый `payin_payout`;
4. `create-payment-for-order` сам выбирает подходящий service-in;
5. контракт API изменился.

## 7. Что не подходит как независимый путь

Сбербанковский MSB-протокол содержит операции создания заказа QR СБП, запроса статуса и возвращает `TAG_TTK_SBP_ORDER_URL`.

Но MSB — это протокол взаимодействия кассы с пинпадом. Он полезен как эталон жизненного цикла QR СБП, **но не является реализацией требования «JL22 без Kozen/пинпада»**.

Аналогично SmartSkyPOS `qrPayment` относится только к `SBP_KOZEN`.

## 8. Что уже готово для прямого JL22

Из текущего Android-кода полностью переиспользуемы:

- локальный `SbpQrRenderer`;
- альбомный экран QR на JL22;
- state machine;
- recovery на Android 6;
- session store;
- idempotency/recovery подход;
- безопасное hash/length logging;
- UI `PAYMENT_ONLINE_QR` / `PAYMENT_ONLINE_CONFIRM`.

Нужно заменить только источник платёжной сессии:

вместо

`Kozen → onQrReading`

должно быть

`ServerSbpPaymentAdapter → create/status API`.

## 9. Чего не хватает

До боевой реализации нужно доказать:

- точный текущий create endpoint;
- точные поля create;
- какой service-in использовать;
- где в ответе QR URL/payload;
- payment id;
- TTL;
- status endpoint;
- финальные статусы success/fail/expired;
- идемпотентность;
- recovery после неизвестного результата create.

Именно это собирает `MAIN_37_SBP_DIRECT_SERVER_READONLY_AUDIT.bat`.

## 10. Архитектурное решение

После аудита создать отдельный:

`DirectSbpPaymentClient` / `ServerSbpPaymentAdapter`.

Этот класс не должен импортировать и вызывать ничего из Kozen/SmartSkyPOS/AOA.

Приёмочный критерий прямого СБП:

**отсоединённый Kozen никак не меняет возможность создать QR, показать его на JL22 и получить серверный final payment status.**
