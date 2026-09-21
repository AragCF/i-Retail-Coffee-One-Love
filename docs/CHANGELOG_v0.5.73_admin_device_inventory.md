# CHANGELOG v0.5.73 — read-only admin device inventory

Дата: 22.09.2026.

## Основание

Публичная документация admin/device доказала наличие:
- `admin/device/create`;
- `admin/device/update`;
- `admin/device/repeat-activation`;
- `admin/device/find`;
- `admin/device/get-device-info`.

До изменения конфигурации нужен полный read-only снимок административных устройств.

## Этот выпуск

Только чтение admin device inventory. Все изменяющие admin/iretail методы запрещены статическими guard-проверками.
