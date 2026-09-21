# CHANGELOG v0.5.66 — read-only аудит источника device_code

Дата: 21.09.2026.

## Основание

Одноразовый register v0.5.64 был явно отклонён сервером:
- HTTP 200;
- API status=false;
- нового device_id нет;
- список устройств не изменился;
- смена 164570 / check_counter 15 не изменилась.

При этом текущий config device_code равен config device_id, что плохо согласуется с документацией register, где требуется encrypted device code.

## Добавлено

- безопасный read-only аудит device/get-by-channel-id + device/get-device-info;
- сравнение серверного code/external_code с config device_code без публикации самих кодов;
- отдельная проверка ZIP;
- автоматическая публикация результата.

## Запрещено

- device/register;
- register-external-system;
- update-info;
- любые shift mutation;
- order synchronize;
- payment creation.

После результата v0.5.66 решение о второй регистрационной попытке принимается отдельно.
