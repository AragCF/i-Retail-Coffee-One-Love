# S3 — безопасные выводы сверки устройства и платёжных служб

Дата: 21.09.2026

## Источник

Живой read-only прогон v0.5.53 был успешно выполнен, но исходный ZIP удалён с вершины публичной ветки из-за обнаруженного пропущенного вложенного token-поля.

Ниже сохранены **только необходимые для S3 не‑секретные выводы**. Значение обнаруженного token-поля намеренно не воспроизводится.

## Устройство канала

Канал:
- channel_id = 5676;
- profile_id = 2512;
- currency_id = 643;
- type = trade_point;
- в канале зарегистрирована ровно одна кофемашина.

Единственное серверное устройство:
- device_id = 3476;
- type = coffee_machine;
- status slug = created;
- condition slug = offline;
- inner_id = 65;
- fiscal_mode = false;
- channel_id = 5676.

Configured `device_id=6287` среди устройств канала отсутствует.

## Актуальность устройства

У устройства 3476:
- last_ping_time: 29.05.2026;
- состояние: offline.

Поэтому устройство нельзя автоматически считать текущей живой кассой только потому, что оно единственное в канале.

## Активная смена

Read-only `shift/get-current-active-shift` для device_id 3476 вернул:
- shift_id = 164570;
- shift number = 23;
- shift status_id = 1 (opening);
- check_counter = 15;
- cashier_opening_id = 3405;
- time_opening: 29.05.2026;
- activeShiftMoreOneDay = true.

Это формально открытая, но явно старая смена. Её нельзя автоматически использовать для нового заказа 21.09.2026.

## Сотрудник

cashier_opening_id совпадает с ранее найденным сотрудником канала:
- employee_id = 3405.

Это подтверждает связь сотрудника 3405 со сменой 164570, но не делает старую смену пригодной для нового заказа.

## Платёжные службы

`service-in/get-used(profile_id=2512)` подтвердил:
- id=3, slug=`external` — наличные;
- id=4, slug=`external_plastic_cards` — внешний эквайринг.

Справочник типов также относит `external_plastic_cards` к карточным службам.

Для Kozen/Vendotek наиболее согласованный **кандидат** — `external_plastic_cards`, но до фиксации жизненного цикла операции это ещё не основание для сетевой отправки.

## Блокер DRY_RUN v2

Для доказанного wire-контракта всё ещё отсутствуют актуальные:
- order_counter;
- operation_counter;
- refund_counter;
- свежая активная смена текущего рабочего устройства.

Документированный `iretail/device/register(device_code)` возвращает именно:
- device_id;
- channel_id;
- device_inner_id;
- counters;
- shift id/check_counter.

Но по названию/назначению метод является регистрационным, а не чисто read-only. Поэтому вызывать его без отдельного контрактного решения нельзя.

## Решение

DRY_RUN v2 может уже включить как доказанные:
- channel_id = 5676;
- currency_id = 643;
- employee_id candidate = 3405;
- payment service candidate for external card terminal = `external_plastic_cards`;
- product type/unit/tax fields из живого каталога и справочников.

Но:
- device_id 3476 нельзя считать текущим автоматически;
- shift_id 164570 нельзя считать текущей сменой;
- counters нельзя выдумывать;
- order/synchronize остаётся запрещён.

Следующее решение по контракту: разрешить либо запретить штатный `device/register(device_code)` как способ получить актуальный device/counters/shift для этой кофемашины.
