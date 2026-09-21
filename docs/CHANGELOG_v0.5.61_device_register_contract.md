# CHANGELOG v0.5.61 — контракт device/register

Дата: 21.09.2026.

## Итог исследования

Расширенный аудит и точный разбор документации установили:

- безопасные методы shift дают только `check_counter`;
- `shift/get-current` способен создать смену и не считается read-only;
- `device/update-info` обновляет сведения об устройстве и не возвращает нужные counters;
- `device/register-external-system` требует `external_code` и является отдельной регистрацией;
- только обычный `device/register(device_code)` документирован как источник device_id + трёх counters + shift/check_counter.

## Этот выпуск

v0.5.61 — контрактный, без рабочего register-вызова.

Добавлены:
- контракт контролируемого одноразового пробника;
- автоматическая проверка контрактных ограничений.

Статус: `PROPOSED_NOT_APPROVED`.
