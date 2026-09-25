# CHANGELOG v0.5.123 — прямой СБП: доступные службы + автоматическая публикация артефактов

Дата: 25.09.2026.

## Новое постоянное правило

Диагностические сценарии, создающие итоговый ZIP/отчёт, больше не должны просить пользователя вручную передавать файл.

Добавлен общий безопасный механизм:

`tools/Publish-TestArtifact.ps1`

Он:

- вычисляет SHA-256;
- создаёт sidecar `.sha256.txt`;
- отказывается работать при уже staged чужих изменениях;
- добавляет только конкретный артефакт и SHA sidecar;
- не использует `git add .`;
- делает отдельный commit;
- push-ит текущую ветку;
- выводит `AUTO_PUBLISH_OK`.

Политика зафиксирована в `docs/AUTOMATIC_ARTIFACT_PUBLICATION.md`.

## Разбор SBP_DIRECT_SERVER_20260925_151950

Read-only аудит подтвердил:

- старого `iretail/order/create-payment-for-order` в текущем apiDoc уже нет;
- `iretail/channel/get-available-services-in` документирован;
- `iretail/payment-in/create` документирован;
- `iretail/payment-in/get-status` документирован;
- `iretail/order/get-payment-data` документирован и возвращает:
  - `payment_in_id`;
  - `payment_link`;
  - `qr_code`;
- глобальный список служб содержит `sbp` и `sbp_low_risk`;
- `service-in/get-used(profile_id=2512)` по-прежнему возвращает только `external` и `external_plastic_cards`.

## Следующий read-only шаг

Добавлен:

`MAIN_38_SBP_DIRECT_SERVICES_READONLY_AUDIT.bat`

Он без Kozen/ADB:

- вызывает `iretail/channel/get-available-services-in` для фактического канала;
- вызывает `service-in/get-used`;
- вызывает `service-in/get-service-in-list`;
- читает последние существующие входящие платежи через `iretail/channel/get-payments-in`;
- не создаёт платежей;
- не создаёт заказ;
- не делает refund/revert;
- автоматически публикует итоговый ZIP в Git.

Цель — доказать конкретный доступный `sbp`/ `sbp_low_risk` service ID/slug и фактическую форму существующих PayIn-PayOut платежей до первого контролируемого create.
