# S3 — результаты аудита зависимостей order/synchronize

Дата: 21.09.2026  
Источник: `test_reports/s3_order_dependencies/S3_ORDER_DEPS_20260921_051456.zip`.

## Результат аудита

- запрошено страниц: 11;
- получено HTTP 200: 11/11;
- ошибок загрузки: 0;
- подтверждённых совпадений: 23;
- сетевые действия: только GET HTML-документации;
- отправка заказа: запрещена.

## 1. Device

`/api/iretail/device/register`

Принимает:
- `device_code`.

Возвращает:
- `device_id`;
- `channel_id`;
- `type_slug`;
- `device_inner_id`;
- `counters`:
  - `order_counter`;
  - `operation_counter`;
  - `refund_counter`;
  - `date`;
- `shift`:
  - `id`;
  - `check_counter`.

Это прямое документальное подтверждение источника верхнеуровневых `counters` и `shift` для synchronize.

Однако `register` не включается в текущий read-only этап, поскольку по названию и назначению он может менять серверное состояние регистрации/контакта устройства.

## 2. Shift

`/api/iretail/shift/get-current-active-shift`

Принимает:
- `device_id`.

Возвращает текущую открытую смену или null. В объекте смены документированы:
- `id`;
- `status_id`;
- `check_counter`;
- `cashier_opening_id`;
- `device_id` и др.

Следовательно:
- `shift_id` можно получить read-only;
- `check_counter` можно получить read-only;
- `cashier_opening_id` является возможным доказанным источником сотрудника текущей смены, но его использование как `orders[].employee_id` нужно подтвердить отдельно.

`open-shift` / `close-shift` используют `employee_id` и `pin`. Это объясняет наличие PIN в соседней документации, но **PIN не является полем synchronize**.

## 3. Employee

`/api/iretail/employee/authorize`

Принимает:
- `device_id`;
- `device_code`;
- `pin`.

Возвращает сотрудника, включая `id`.

`/api/iretail/employee/get-by-channel` принимает `channel_id` и возвращает список сотрудников канала.

Вывод: `employee_id` имеет документированный источник. Но для полностью автономной кофемашины ещё нужно определить бизнес-правило: использовать сотрудника открытой смены, специального системного сотрудника или иной серверно настроенный ID.

## 4. Статусы

В `/api/reference` есть отдельные read-only методы:

- `get-order-status`;
- `get-order-statuses`;
- `get-order-payment-status`;
- `get-statuses-operation`;
- `get-types-operation`;
- `get-statuses-shift`;
- `get-currencies`;
- `get-types-offer`.

Следовательно, `order_status_id` и `payment_status_id` нельзя зашивать предположением — их нужно получить из актуального справочника.

## 5. Платёжная служба

`/api/service-in/get-service-in` возвращает PayIn-PayOut службы:
- `id`;
- `slug`;
- `title`;
- `name`;
- `title_lang_data`.

`get-service-in-list` возвращает PayIn-PayOut + i-Retail службы.

`get-service-in-types` группирует их по типам:
- cash;
- card;
- account.

Следовательно, `service_in_slug` для CARD/SBP нельзя придумывать. Его нужно выбрать из фактически настроенных серверных служб.

## 6. Payment-in

`/api/iretail/payment-in/create` подтверждает использование:
- `device_id`;
- `sum`;
- `order_number`;
- `service_in_id` либо `service_in_slug`;
- optional phone.

Это отдельный PayIn-PayOut контур и не является доказательством того, что локально подтверждённый Kozen-платёж должен создавать payment-in этим методом.

## 7. Offer / продукт

Живой ZIP-каталог реально содержит для наших 8 кофейных товаров:
- внутренний `id`;
- `id_yml`;
- `name`;
- `type_id=7`;
- `unit_id=10`;
- `currency_id=RUB` как сырое значение каталога;
- `price`;
- `base_price`;
- `tax_id=29259`;
- `gcode`.

При этом synchronize требует/описывает дополнительные поля, в том числе:
- uuid;
- commit_time;
- tax_rate;
- tax_included_in_price;
- tax_number_in_printer;
- numeric/contract currency_id.

Каталог не даёт достаточного доказательства для всех этих полей.

## 8. Tax

`/api/iretail/tax/get` позволяет получить VAT rates по `profile_id`.

Следовательно, `tax_id` из каталога нельзя автоматически трактовать как `tax_rate`; нужна отдельная read-only выборка налогов профиля.

## 9. Нумерация

Order apiDoc подтверждает:
- `get-last-offline-order-number(device_id,date)`;
- `order_number`;
- `short_number`;
- `number_to_day`.

Но алгоритм формирования полного и короткого номера из документации всё ещё не доказан.

## 10. Решение

Перед DRY_RUN v2 выполнить read-only живой аудит:

- reference statuses/currencies/types;
- service-in lists/types;
- shift/get-current-active-shift;
- employee/get-by-channel;
- device/get-device-info;
- tax/get.

Не вызывать:
- order/synchronize;
- device/register;
- open-shift/close-shift;
- employee/authorize;
- payment-in/create.

После этого построить DRY_RUN v2 только из доказанных значений.
