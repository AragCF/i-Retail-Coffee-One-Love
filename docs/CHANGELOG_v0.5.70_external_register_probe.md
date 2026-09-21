# CHANGELOG v0.5.70 — controlled register-external-system probe

Дата: 22.09.2026.

## Разрешение

Контракт v1.0.0 получил статус `APPROVED_FOR_SINGLE_PROBE` после явного сообщения пользователя:

«Одобряю один пробный register-external-system».

## Реализовано

- источник external_code — только server-side device 3476;
- external_code не сохраняется;
- две устойчивые одноразовые marker-метки;
- ровно один register-external-system;
- retry=0;
- redirects отключены;
- безопасный ответ без секретов;
- read-only состояние устройств/смен после вызова;
- отдельный recovery без регистрации;
- автоматическая публикация ZIP после двойной проверки.

## Запрещено

- повторный ordinary device/register;
- order/synchronize;
- payment create;
- shift mutation;
- employee authorize;
- device/update-info;
- любые команды кофемашине;
- автоматическая привязка returned device.
