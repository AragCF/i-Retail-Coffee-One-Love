# CHANGELOG v0.5.59 — точный разбор device counter methods

Дата: 21.09.2026.

## Основание

Аудит v0.5.57 и автоматический разбор v0.5.58 доказали:

- read-only shift-методы возвращают только `check_counter`;
- `shift/get-current` нельзя считать чистым чтением, поскольку документация допускает создание смены;
- полный набор `order_counter / operation_counter / refund_counter` встречается только рядом с device-методами и `order/synchronize`.

## Добавлено

`tools/analyze_s3_device_counter_methods.py` извлекает из опубликованного ZIP полный документальный блок для:

- `device/register`;
- `device/register-external-system`;
- `device/update-info`.

Никаких рабочих API-вызовов не выполняется.

## Автоматизация

Документальный разбор вынесен в отдельную быструю задачу GitHub Actions. Android-сборка продолжает выполняться независимо.
