# CHANGELOG v0.5.91 — fiscal positive DRY_RUN self-test

Дата: 23.09.2026.

Добавлен безопасный положительный self-test FiscalGateway на живой JL22 без финансовой операции.

Проверяется:
PAID + CARD synthetic RuntimeOrder → FiscalGateway → DRAFT_READY → fiscalization_dry_run.json.

Kozen, PAYMENT, cloud-fiscal и order/synchronize не используются.
