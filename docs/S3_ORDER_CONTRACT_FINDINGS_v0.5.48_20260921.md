# S3 — результаты аудита актуального контракта заказа I-Retail

Дата: 21.09.2026  
Источник доказательств: `test_reports/s3_order_contract/S3_ORDER_DOCS_20260921_040147.zip`.

## Статус

Аудит документации выполнен успешно:
- apiDoc index: HTTP 200;
- найдено 10 ссылок на order-controller страницы, соответствующих 5 уникальным страницам;
- все 10 запросов вернули HTTP 200;
- сетевые действия аудита: только GET документации;
- отправка заказа: запрещена.

Главная страница для терминального контура:

`/api/iretail/order`

Страница опубликована как `actual`, но сама HTML-страница сгенерирована 31.08.2022. Поэтому это наиболее актуальная **опубликованная** документация сервера, но не доказательство того, что серверная реализация не менялась после этой даты.

## 1. Важное изменение понимания

Текущий локальный DRY_RUN v0.5.37–0.5.48 нельзя превращать в сетевой запрос простым включением отправки.

Его `candidate_request` сейчас содержит:

- `id`;
- `channel_id`;
- `sum`;
- `device_id`;
- `device_code`;
- `employee_id`;
- `pin`;
- `currency_id`;
- `time_create`;
- `products[{offer_id, quantity, price}]`.

Документированный `/api/iretail/order/synchronize` имеет существенно другую структуру.

## 2. Документированный synchronize

Маршрут:

`POST /api/iretail/order/synchronize`

Назначение: синхронизация до 200 заказов за один запрос.

### Верхний уровень

Документированы:

- `device_id`;
- `counters`:
  - `order_counter`;
  - `operation_counter`;
  - `refund_counter`;
  - `date`;
- `shift`:
  - `id`;
  - `check_counter`;
- `orders` — массив заказов;
- `operations` — массив ручных операций.

### Обязательная часть элемента orders до пометки Optional

Документация перечисляет:

- `employee_id`;
- `channel_id`;
- `sum`;
- `shift_id`;
- `device_id`;
- `order_status_id`;
- `payment_status_id`;
- `order_number`;
- `short_number`;
- `number_to_day`;
- `time_create`;
- `service_in_slug`.

После этого в документации начинается секция `Optional:`.

### Дополнительные поля заказа

В опубликованной структуре далее описаны, в частности:

- `discount_sum`;
- `ibonus_discount_sum`;
- `ibonus_discount_currency`;
- `promocode`;
- `check`;
- `client_id`;
- `phone`;
- `egais`;
- `comment`;
- `comments`;
- `client_contact_details`;
- `payment_in_id`;
- `forward_number`;
- `services`;
- `discounts`;
- `products`;
- `operations`;
- `status_history`;
- `payment_status_history`.

Нельзя автоматически считать все перечисленные после слова Optional обязательными. Для нашего кофейного заказа нужно определить минимально допустимую подструктуру опытным чтением связанных apiDoc и, только затем, безопасным стендовым запросом.

## 3. products в synchronize

Продукт в `orders[].products[]` описан значительно богаче текущего DRY_RUN.

Документированы:

- `uuid`;
- `offer_id`;
- `id_yml`;
- `name`;
- `type_id`;
- `unit_id`;
- `quantity`;
- `commit_time`;
- `base_price`;
- `price`;
- `tax_rate`;
- `tax_included_in_price`;
- `tax_number_in_printer`;
- `excise_mark_barcodes`;
- `currency_id`;
- `discount_sum`;
- `is_coupon`;
- `coupon_token`;
- `modifier_option_id`;
- `barcode`;
- вложенные `discounts`;
- вложенные `nestedProducts`.

Текущие `offer_id + quantity + price` недостаточны, чтобы считать payload synchronize доказанным.

## 4. Ответ synchronize

Документация возвращает:

`{ task_id: int }`

То есть синхронизация асинхронная.

Для проверки результата документирован:

`POST /api/iretail/order/get-info-on-task-id`

Вход:
- `task_id`.

Ответ содержит `orders` и `operations`, где для элемента заказа описаны:

- `order_number` — номер из запроса синхронизации;
- `order_id` — ID, созданный на сервере;
- `status_id`:
  - 1 — Queued;
  - 2 — Processing;
  - 3 — Done;
  - 4 — Failed.

Ошибка 166: Task not found.

Для synchronize документирована ошибка 167: Task creation failed.

Следовательно, считать HTTP-ответ synchronize непосредственным подтверждением создания заказа нельзя. Нужно сохранять `task_id` и опрашивать состояние задачи.

## 5. Нумерация офлайн-заказов

Документирован:

`POST /api/iretail/order/get-last-offline-order-number`

Поля:
- `device_id`;
- `date` в формате YYYY-MM-DD.

Ответ:
- последний порядковый номер для указанной даты либо null.

Это подтверждает, что `number_to_day`, счётчики и номера устройства являются частью офлайн-синхронизации. Но точный алгоритм сборки `order_number` и `short_number` из одной этой страницы не доказан.

## 6. reserve-order-id

Строка `reserve-order-id` **не найдена ни на одной из пяти уникальных order-controller страниц**, загруженных из текущего `actual` apiDoc.

Поэтому прежнее предположение:

`reserve-order-id → id → order/synchronize`

не подтверждается текущей опубликованной документацией и не должно использоваться как основание для сетевой реализации.

Это не доказывает, что такой маршрут никогда не существовал; лишь что в текущем опубликованном order apiDoc его нет.

## 7. pin

Точного параметра/поля `pin` в `/api/iretail/order/synchronize` не обнаружено.

Первичный поиск дал совпадения по подстроке `pin`, но проверка целого слова показала, что это ложные совпадения внутри других слов/фрагментов HTML.

Следовательно, текущий `pin=null` в DRY_RUN не подтверждается актуальной страницей order/synchronize.

## 8. Поля текущего DRY_RUN: сверка

| Поле текущего черновика | synchronize apiDoc |
|---|---|
| id | не документировано в orders[] |
| channel_id | документировано |
| sum | документировано |
| device_id | документировано и сверху, и внутри заказа |
| device_code | не документировано |
| employee_id | документировано; источник значения ещё нужен |
| pin | не документировано как поле synchronize |
| currency_id | не документировано на уровне заказа; есть внутри products[] |
| time_create | документировано |
| products.offer_id | документировано |
| products.quantity | документировано |
| products.price | документировано, но продукт требует/описывает намного больше полей |

## 9. Идемпотентность и повтор

В загруженной order-документации явных терминов/правил `idempotency` или `retry` не найдено.

Из асинхронной модели следует безопасный принцип для нашей реализации:

- после получения `task_id` нельзя автоматически создавать новую synchronization-задачу только потому, что ответ отдельного опроса временно не получен;
- сначала нужно восстановить состояние уже созданной задачи через `get-info-on-task-id`.

Это инженерный вывод из документированной асинхронной модели, а не прямое правило apiDoc.

## 10. Что ещё требуется доказать

До реализации сетевой отправки нужно получить связанные страницы apiDoc для:

1. `iretail/device` — устройство, счётчики и идентификаторы;
2. `iretail/shift` — shift_id и check_counter;
3. `iretail/employee` — источник employee_id;
4. статусов заказа и оплаты — допустимые order_status_id/payment_status_id;
5. `service_in_slug` — корректное значение для CARD / SBP / иных методов;
6. каталога/offer — type_id, unit_id, tax, currency и прочие поля продукта;
7. нумерации заказа — order_number/short_number/number_to_day;
8. возможной схемы UUID/commit_time/status history.

## Решение на текущем шаге

**Реальную отправку synchronize не включать.**

Текущий DRY_RUN полезен как доказательство суммы и базовых товарных строк, но его payload не является точным wire-контрактом synchronize.

Следующий безопасный шаг — read-only аудит связанных apiDoc-контроллеров и построение нового DRY_RUN v2 по доказанному контракту.
