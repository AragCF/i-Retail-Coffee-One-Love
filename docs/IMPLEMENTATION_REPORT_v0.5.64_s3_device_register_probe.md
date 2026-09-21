# Отчёт реализации v0.5.64 — S3 device/register probe

## Цель

Один раз выполнить одобренный штатный `device/register`, получить актуальные device/counters/shift и доказательно сравнить серверное состояние до и после.

## Защита от повторов

Основной сценарий создаёт две метки до сетевого register-вызова:

1. `test_reports/s3_device_register/DEVICE_REGISTER_PROBE_1_0_1.marker.json`;
2. `%LOCALAPPDATA%\CoffeeOneLove\iRetail\S3\device_register_probe_contract_1_0_1.json`.

Если присутствует хотя бы одна метка, основной сценарий прекращается до register.

При неопределённом результате метка не удаляется.

## Неопределённый ответ

Тайм-аут, сетевой сбой или неразбираемый ответ классифицируется как `REGISTER_RESULT_UNCERTAIN`. Повтор запрещён; для дополнительного наблюдения используется только `S3_16_COLLECT_DEVICE_REGISTER_STATE_ONLY.bat`.

## Серверный результат

Отчёт сохраняет только безопасные:
- returned device_id;
- type_slug;
- channel_id;
- counters;
- shift;
- список устройств до/после;
- новые device IDs;
- read-only состояние смен.

Учётные данные, access token и device_code в ZIP не публикуются.

## Следующий шаг

Только анализ живого ZIP. Даже успешный register не включает order synchronize.
