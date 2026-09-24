# CHANGELOG v0.5.107 — declined payment read-only recovery

Дата: 24.09.2026.

Единственная разрешённая карточная попытка на 1,00 ₽ была фактически заявлена приложением и завершилась определённым `DECLINED`. Пользователь подтвердил, что карту приложил и терминал показал отказ.

Санитизированный отчёт подтвердил:
- `TEST_MODE_READY` до оплаты;
- `ATTEMPT_CLAIMED`;
- `TEST_RESULT status=DECLINED code=0 amount=1.00`;
- persisted real POS после завершения снова false;
- fiscalization_dry_run отсутствует.

Поле `code=0` само по себе не означает одобрение: в восстановленном SmartSkyPOS-контракте отсутствующий ключ code читается как 0. В старом живом отказе от 14.09.2026 определяющими были `approved=false` и `rc=99`.

Добавлено:
- `KozenAoaPaymentClient.readLastTransaction()` — только GET_STATE / GET_TERMINAL_DATA / GET_LAST_TRANSACTION / GET_TRANSACTION;
- intent `fiscal_declined_payment_recovery=true` в основном i-Retail при realPos=false;
- `MAIN_28_DECLINED_PAYMENT_READONLY_RECOVERY.bat`;
- автоматическая санитизация и публикация отчёта;
- исправлен filter-spec `IretailKozenClient` в MAIN_26: один `:V` вместо повторных I/W/E, чтобы не терять `PAYMENT_TX_ONCE`.

Новый PAYMENT под текущим контрактом запрещён. Recovery не меняет финансовое состояние.