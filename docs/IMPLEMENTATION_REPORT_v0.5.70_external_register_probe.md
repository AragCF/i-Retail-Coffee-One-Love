# Отчёт реализации v0.5.70 — S3 external-system register probe

## Цель

Проверить одну рабочую гипотезу: server-side `external_code` coffee_machine 3476 предназначен для регистрации внешней системы через `device/register-external-system`.

## Последовательность

1. Авторизация.
2. Read-only снимок устройств/смен «до».
3. Read-only device-info 3476.
4. Извлечение external_code только в память.
5. Создание двух marker-файлов.
6. Ровно один register-external-system, без redirect/retry.
7. Безопасное сохранение результата.
8. Read-only снимок «после».
9. ZIP-проверка и публикация.

## Защита от повторов

- repo marker: `test_reports/s3_external_register/EXTERNAL_SYSTEM_REGISTER_PROBE_1_0_0.marker.json`;
- Windows marker: `%LOCALAPPDATA%\CoffeeOneLove\iRetail\S3\external_system_register_probe_contract_1_0_0.json`.

Любая метка блокирует новый изменяющий запуск.

## Секретность

External code никогда не сохраняется в отчёт. После его получения он добавляется в набор значений, которые запрещено обнаружить в публикуемых txt/json.

## После живого опыта

Никакой order/synchronize автоматически не включается. Сначала анализируется ZIP.
