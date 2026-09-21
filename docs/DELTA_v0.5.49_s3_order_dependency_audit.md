# DELTA v0.5.49 — read-only аудит зависимостей заказа S3

Дата: 21.09.2026

## Основание

Аудит `/api/iretail/order/synchronize` показал, что текущий ранний DRY_RUN не соответствует полному wire-контракту офлайн-синхронизации.

До реализации сетевого запроса необходимо доказать источники и допустимые значения:

- `employee_id`;
- `shift_id` и `check_counter`;
- `order_status_id`;
- `payment_status_id`;
- `service_in_slug`;
- счётчиков устройства;
- `order_number / short_number / number_to_day`;
- полей товара `type_id / unit_id / tax / currency / uuid / commit_time`.

## Цель

Скачать только документацию связанных контроллеров из актуального apiDoc и сохранить доказательства в Git.

## 🟢 Проверяемые страницы

- `/api/iretail/device`;
- `/api/iretail/shift`;
- `/api/iretail/employee`;
- `/api/iretail/operation`;
- `/api/iretail/payment-in`;
- `/api/iretail/channel`;
- `/api/iretail/offer`;
- `/api/iretail/catalog`;
- `/api/iretail/tax`;
- `/api/reference`;
- `/api/service-in`.

## 🔴 Не выполняется

- создание заказа;
- `order/synchronize`;
- изменение заказа;
- оплата;
- фискализация.

Все сетевые обращения этого этапа — только GET к HTML-документации.

## Следующий шаг после аудита

Построить новый `DRY_RUN v2` только из подтверждённых полей и отдельно показать пользователю контрактный DELTA перед реализацией сетевой отправки.
