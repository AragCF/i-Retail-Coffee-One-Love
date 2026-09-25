# Контракт двух независимых контуров СБП v2.0.0

Дата: 25.09.2026  
Статус: **REQUIREMENT_CONFIRMED / DIRECT_SERVER_CONTRACT_AUDIT_IN_PROGRESS**

## 1. Обязательное требование

i-Retail обязан поддерживать **два независимых способа СБП**.

### A. SBP_KOZEN

Платёжный контур использует отдельный платёжный терминал Kozen P12 / SmartSkyPOS:

`JL22 → USB/AOA → Kozen Bridge → SmartSkyPOS → банк`.

Этот контур может использовать возможности `qrPayment`, callback `onQrReading` и интерфейс самого Kozen.

### B. SBP_DIRECT_JL22

Платёжный контур **не использует Kozen ни как транспорт, ни как источник QR, ни как источник статуса**:

`JL22 → серверный/банковский СБП API → QR URL/payload → локальный QR renderer JL22 → серверный статус оплаты`.

Kozen может быть:
- выключен;
- физически отсоединён;
- не установлен рядом с кофемашиной.

`SBP_DIRECT_JL22` при этом обязан продолжать работать.

Наличие `SBP_KOZEN` не заменяет `SBP_DIRECT_JL22` и наоборот.

## 2. Найденные источники для SBP_DIRECT_JL22

### 2.1. Старый TSO-контур i-Retail

В `docs/TSO_REFERENCE_NOTES_v0.4.md` по исходникам `net.payinpayout.tso-master.tar.gz` зафиксированы серверные команды:

- `order/reserve-order-id`;
- `order/create`;
- `order/pay`;
- `order/get-by-id`;
- `iretail/channel/get-available-services-in`;
- `iretail/order/create-payment-for-order`;
- `iretail/check/send`.

Особенно важны:

- `iretail/channel/get-available-services-in` — получение доступных способов оплаты;
- `iretail/order/create-payment-for-order` — создание онлайн-платежа.

Это доказывает наличие исторического серверного пути онлайн-оплаты, который архитектурно не требует локального Kozen Bridge.

### 2.2. Старый pay-methods.xml

В `app/src/main/assets/content/pay-methods.xml` присутствует отдельный включённый серверный способ:

- id=`7777`;
- slug=`payin_payout`;
- currency=`RUB`;
- title=`Online`;
- enabled=`true`.

Он существует отдельно от:

- `external_plastic_cards` — внешний карточный эквайринг;
- `external` — наличные.

Это дополнительно подтверждает отдельную модель онлайн-платежа.

### 2.3. Актуальный i-Retail API

Документальный аудит уже установил:

`/api/iretail/payment-in/create` принимает как минимум:

- `device_id`;
- `sum`;
- `order_number`;
- `service_in_id` либо `service_in_slug`;
- optional `phone`.

Живой read-only справочник `service-in/get-service-in-list` ранее возвращал, среди прочего:

- `sbp`;
- `sbp_low_risk`;
- `external`;
- `external_plastic_cards`;
- `external_plastic_nonitgerated`;
- `goswiff`;
- `payme_alfa`;
- `i_bonus`.

Следовательно, текущий backend знает сущности СБП на уровне service-in.

При этом `service-in/get-used(profile_id=2512)` на прошлом живом аудите подтвердил для текущего профиля только:

- `external`;
- `external_plastic_cards`.

Поэтому **нельзя пока молча выбрать `sbp` или `sbp_low_risk` как боевой service_in_slug**. Нужно доказать, какая служба доступна текущему каналу/профилю и какой серверный метод создаёт QR.

## 3. Что уже готово и можно переиспользовать

От веток 0.5.110–0.5.120 для прямого контура переиспользуются только независимые от Kozen части:

- `PAYMENT_ONLINE_QR`;
- `PAYMENT_ONLINE_CONFIRM`;
- локальный `SbpQrRenderer`;
- машина состояний СБП;
- сохранение и восстановление сессии;
- Android 6-safe recovery;
- срок жизни/идемпотентность;
- защита от двойной оплаты;
- безопасное журналирование hash/length вместо сырого QR;
- fail-closed при неопределённости.

Не переиспользуются в `SBP_DIRECT_JL22`:

- `KozenAoaPaymentClient`;
- `ProductionBridgeService`;
- USB/AOA;
- SmartSkyPOS Binder;
- `qrPayment #19`;
- `onQrReading` Kozen;
- состояние/доступность Kozen.

## 4. Требуемый адаптер прямого СБП

Новый адаптер должен быть отдельным, например:

`DirectSbpPaymentClient` / `ServerSbpPaymentAdapter`.

Его минимальный контракт:

### createPayment

Вход:
- локальный correlation/request id;
- номер заказа;
- сумма в копейках;
- валюта 643;
- серверный идентификатор устройства/канала, только если он реально требуется подтверждённым API;
- доказанный `service_in_id` или `service_in_slug`.

Выход:
- server payment id / transaction id;
- QR URL или QR payload;
- срок действия;
- начальный серверный статус.

### getStatus

Вход:
- тот же server payment id / transaction id.

Выход:
- authoritative status;
- признак окончательности;
- время обновления;
- безопасный код ошибки.

### cancel/refund

До отдельного контракта эти операции не выполняются автоматически.

## 5. Машина состояний

Рекомендуемый общий контракт:

`IDLE → CREATING → QR_READY → WAITING → PAID / DECLINED / EXPIRED / CANCELLED / UNCERTAIN / ERROR`.

Правила:

- повторное открытие QR-экрана не создаёт второй платёж;
- timeout сетевого запроса после отправки create не означает, что create не состоялся;
- при неопределённости сначала recovery/status по correlation id, а не новая create;
- показ QR не равен оплате;
- факт сканирования QR клиентом не равен оплате;
- только authoritative server status может дать `PAID`;
- только после `PAID` разрешаются последующие бизнес-этапы заказа.

## 6. QR на JL22

QR строится **локально** из серверного URL/payload через существующий `SbpQrRenderer`.

Запрещено:
- передавать платёжный payload внешнему генератору QR;
- писать raw URL/payload в журналы;
- хранить его дольше необходимого срока жизни;
- считать успешным платёж только потому, что QR отображён или считан.

## 7. Независимость от Kozen — проверяемый инвариант

Прямой СБП должен проходить тест при полном отсутствии Kozen.

Для `SBP_DIRECT_JL22` запрещены зависимости кода от:

- USB/AOA;
- VID/PID Kozen;
- `com.skytech.smartskypos`;
- `KozenAoaPaymentClient`;
- `ProductionBridgeService`;
- Binder transaction #19.

Приёмочный тест должен иметь вариант:

`KOZEN_NOT_CONNECTED_EXPECTED=true`.

## 8. Что ещё нужно доказать до боевого create

Нужно получить из актуальной документации и read-only API:

1. точный текущий метод создания независимого online/SBP payment;
2. является ли актуальным `iretail/order/create-payment-for-order`;
3. роль `iretail/payment-in/create` для СБП;
4. точный `service_in_slug/id` для текущего профиля/канала;
5. поля запроса create;
6. поля ответа с QR URL/payload;
7. payment/transaction id;
8. TTL / expires_at;
9. точный read-only метод проверки статуса;
10. перечень final/non-final статусов;
11. правила идемпотентности;
12. recovery после timeout/restart.

До доказательства этих пунктов боевой серверный SBP create не реализуется догадками.

## 9. Следующий безопасный этап

Выполнить отдельный read-only аудит серверного контракта **без Kozen**:

- скачать актуальные apiDoc страниц order/payment-in/channel/service-in;
- найти документированные `create-payment-for-order`, `get-available-services-in`, `payment-in/create`;
- прочитать только справочники service-in текущего профиля/канала;
- собрать безопасный отчёт;
- не создавать order/payment/payment-in;
- не устанавливать и не проверять Kozen Bridge.

После этого реализовать `DirectSbpPaymentClient` по фактически доказанному серверному контракту.
