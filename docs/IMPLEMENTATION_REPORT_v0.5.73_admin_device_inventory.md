# Отчёт реализации v0.5.73 — S3 admin device inventory

## Цель

Проверить, создана ли уже кассовая/self-service сущность, которую методы register ожидают активировать, и идентифицировать configured device_id 6287.

## Read-only вызовы

- admin/device/get-count-device-in-channel;
- admin/device/find;
- admin/device/get-device-info;
- admin/device/get-list-device-involved-in-orders.

## В отчёте

Для каждого кандидата сохраняются только безопасные признаки:
- device_id;
- type slug/id;
- channel_id;
- status/condition;
- own_orders;
- fiscal_mode;
- inner_id;
- наличие и длина code/external_code;
- признаки configured device / coffee machine / cashbox.

Сами code/external_code и персональные данные не публикуются.

## Запрещено

Create/update/repeat-activation/remove/restore/block/unlock, обе регистрации, order synchronize, payment и shift mutation.
