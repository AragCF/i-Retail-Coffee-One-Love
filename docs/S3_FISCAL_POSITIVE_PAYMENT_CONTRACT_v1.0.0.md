# S3 — контролируемая положительная проверка FiscalGateway после реальной оплаты

Версия контракта: 1.0.0  
Версия проекта: 0.5.90  
Дата: 23.09.2026  
Статус: **PROPOSED_NOT_APPROVED**

## Цель

Однократно доказать на живой JL22 цепочку:

`ручной выбор оплаты → Kozen/SmartSkyPOS APPROVED → RuntimeOrder=PAID → FiscalGateway → DRAFT_READY → fiscalization_dry_run.json`

При этом:
- настоящий Fiscal API НЕ вызывается;
- `iretail/order/synchronize` НЕ вызывается;
- приготовление кофе НЕ запускается;
- повтор финансовой операции не выполняется автоматически.

## Предпосылки

Уже подтверждено живым v0.5.89:
- JL22 определяется корректно через любой живой ADB-интерфейс;
- i-Retail работает в persistent `standalone`;
- `real_pos_enabled=false` безопасно блокирует оплату;
- без подтверждённой оплаты Fiscal DRY_RUN не создаётся;
- i-Retail остаётся на переднем плане.

## Разрешённый тест после явного одобрения

Ровно одна попытка реальной карточной оплаты из основного UI.

Ограничения заказа:
- одна товарная позиция;
- количество 1;
- без карты лояльности;
- без списания бонусов;
- без купона;
- без сиропа;
- без «своего стакана»;
- итоговая сумма не более 100 ₽; предпочтительно минимальная доступная сумма.

Инициация:
- только человеком на экране JL22;
- только одним нажатием «Банковская карта»;
- Windows-сценарий сам команду PAYMENT не отправляет.

## Защита от повтора

До включения real POS должны быть созданы устойчивые marker-файлы контракта 1.0.0.

После начала попытки:
- автоматический retry запрещён;
- второй ручной тап запрещён;
- при `UNCERTAIN`, timeout, потере связи или неполном ответе повтор запрещён до отдельного read-only восстановления;
- marker не удаляется и не переиспользуется.

## Ожидаемый путь при APPROVED

1. Kozen возвращает достоверный `APPROVED`.
2. `LocalRetailOrderGateway.markPaymentConfirmed()` переводит заказ в `PAID`.
3. `FiscalGateway.afterPaymentConfirmed(order)` вызывается один раз.
4. Единственный активный provider — `DryRunFiscalGateway`.
5. Он возвращает:
   - `state=DRAFT_READY`;
   - `sendAllowed=false`;
   - `receiptUrl=null`;
   - локальный `fiscalization_dry_run.json`.
6. Никакой HTTP-запрос к cloud-fiscal не выполняется.

## Что проверяем в fiscalization_dry_run.json

- `mode = DRY_RUN_ONLY`;
- `send_allowed = false`;
- `network_actions = NONE`;
- `credentials_present = false`;
- `order_state = PAID`;
- `payment_method = CARD`;
- `products_count = 1`;
- `gross_matches_runtime = true`;
- `payable_equation_matches = true`;
- `card_amount` совпадает с реально оплаченной суммой;
- `external_order_id` присутствует;
- товар, цена и количество соответствуют заказу;
- unresolved содержит только ожидаемые блокеры текущего исторического Fiscal API, а не ошибки денежного маппинга.

## Что делаем после финального результата

Независимо от APPROVED/DECLINED:
- `real_pos_enabled` возвращается в `false`;
- `machine_mode` остаётся `standalone`;
- i-Retail остаётся на переднем плане;
- создаётся ZIP-отчёт;
- финансовые/карточные данные санитизируются;
- отчёт публикуется в Git только после safety scan.

При `UNCERTAIN`:
- real POS также выключается;
- отчёт собирается;
- никаких новых платежей до разбора результата.

## Жёстко запрещено

- автоматический повтор PAYMENT;
- второй PAYMENT в рамках этого контракта;
- `iretail/order/synchronize`;
- любой `cloud-fiscal/order/create` или другой боевой Fiscal API;
- `device/register`;
- `device/register-external-system`;
- `admin/device/create`;
- открытие/закрытие смены;
- запуск приготовления;
- публикация PAN, track data, PIN, токенов, секретов, device_code/external_code.

## Условие перехода к реализации

Нужно отдельное явное подтверждение пользователя на **одну** реальную карточную оплату по этому контракту.

До подтверждения этот документ не даёт права включать `real_pos_enabled=true` или выполнять финансовую операцию.
