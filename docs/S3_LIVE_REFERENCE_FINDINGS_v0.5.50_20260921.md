# S3 — результаты живого read-only аудита справочников

Дата: 21.09.2026  
Источник: `test_reports/s3_live_reference/S3_LIVE_REF_20260921_052946.zip`.

## Общий результат

- авторизация: HTTP 200, API status=true;
- read-only запросов: 15;
- HTTP 2xx: 15/15;
- JSON успешно разобран: 15/15;
- проверка отчёта на секреты: успешно;
- order/synchronize и другие изменяющие состояние методы не вызывались.

## Подтверждённые значения

### Статусы заказа

Справочник содержит, в частности:
- 1 — Новый;
- 2 — В обработке;
- 3 — Обработан;
- 5 — Ожидание оплаты;
- 13 — Ожидает фискализации.

Нельзя выбирать order_status_id только по названию без фиксации жизненного цикла заказа и фискализации.

### Статусы оплаты

Подтверждены:
- 1 — status_not_payed;
- 2 — status_payed;
- 5 — status_payed_by_pin_pad;
- 6 — status_error;
- 9 — status_awaiting_payment;
- и другие.

Для подтверждённого терминального карточного платежа ID 5 семантически соответствует «Оплачен с Pin-Pad», но его использование в нашем Kozen/Vendotek контуре ещё требует явного контрактного решения.

### Операция продажи

Тип операции:
- id=1;
- slug=sale.

Успешный статус операции:
- id=2;
- «Проведена».

### Валюта

Справочник вернул:
- id=643;
- описание: «Рубль России».

Это подтверждает числовой currency_id=643.

### Тип товара

Живой каталог использует type_id=7.

Справочник подтверждает:
- id=7;
- slug=technology_card_gcode;
- «Технологическая карта с GCode»;
- default unit_id=10;
- unit_id=10 — «нет единицы измерения».

### Налог

Живой каталог для всех восьми проверенных кофейных товаров содержит tax_id=29259.

Живой налоговый справочник подтверждает tax 29259:
- «НДС не облагается»;
- rate=0;
- tax_included_in_price=false;
- number_in_printer=4;
- active=true.

Следовательно, для этих товаров доказаны:
- tax_rate=0;
- tax_included_in_price=false;
- tax_number_in_printer=4.

### Сотрудник

`employee/get-by-channel` успешно вернул:
- employee_id=3405;
- status=worked;
- is_merchant=true.

Имя и PIN удалены из опубликованного отчёта.

Этот ID является реальным сотрудником канала 5676 и допустимым кандидатом для `orders[].employee_id`, но бизнес-правило выбора сотрудника автономной кофемашины нужно зафиксировать отдельно.

## Платёжные службы

`service-in/get-service-in-list` вернул, в частности:
- sbp;
- sbp_low_risk;
- external;
- external_plastic_cards;
- external_plastic_nonitgerated;
- goswiff;
- payme_alfa;
- i_bonus.

`get-service-in-types` относит к card:
- paynet;
- inpas_in;
- payme_alfa;
- goswiff;
- external_plastic_cards;
- external_plastic_nonitgerated.

Но `service-in/get-service-in` вернул API error:
- ожидается `profile_id`.

Это противоречит/дополняет опубликованную в 2022 страницу apiDoc, где параметр не был указан.

Поэтому конкретный slug для Kozen/Vendotek пока не выбирается.

## Критический блокер устройства

Для configured device_id=6287:

`iretail/device/get-device-info`:
- HTTP 200;
- API status=false;
- title=error.cashboxNotFind.

`iretail/shift/get-current-active-shift`:
- HTTP 200;
- API status=false;
- title=error.cashboxNotFind.

Следовательно, текущий device_id=6287 достаточен для уже работающего каталожного контура, но **не доказан как действующая касса для offline order synchronize**.

Нельзя выдумывать:
- shift_id;
- check_counter;
- order_counter;
- operation_counter;
- refund_counter.

## Решение

Перед DRY_RUN v2 выполнить ещё один read-only live audit:

1. `iretail/device/get-by-channel-id(channel_id=5676)`;
2. безопасно перечислить реальные device IDs канала;
3. для каждого найденного device ID (с ограничением количества) прочитать:
   - device/get-device-info;
   - shift/get-current-active-shift;
4. `service-in/get-service-in(profile_id=2512)`;
5. `service-in/get-used(profile_id=2512)`;
6. `iretail/channel/get(channel_id=5676)`.

После этого:
- не выбирать устройство автоматически при неоднозначности;
- не регистрировать устройство;
- не открывать смену;
- не создавать заказ;
- построить DRY_RUN v2 только после доказательства корректного кассового device ID и платёжной службы.
