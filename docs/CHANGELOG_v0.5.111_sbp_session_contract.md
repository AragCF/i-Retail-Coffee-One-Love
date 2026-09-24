# CHANGELOG v0.5.111 — SBP session contract and recovery

Дата: 24.09.2026.

Продолжение безопасного этапа S4.

Добавлено:
- production-neutral `SbpProductionContract`: operation type 42, transactionType qrPayment, currency 643, Binder slot 19;
- `LIVE_CALL_ENABLED=false` как явный предохранитель до отдельного финансового разрешения;
- полноценные состояния сессии: QR_READY / WAITING / PAID / DECLINED / EXPIRED / CANCELLED / UNCERTAIN / ERROR;
- приватное SharedPreferences-хранилище `iretail_sbp_session_v1`;
- qrId/payload сохраняются только внутри приложения для восстановления;
- в журналы выводятся только SHA-256 отпечатки и длина payload;
- dry-run session умеет восстанавливаться после process restart;
- если активная сессия существует, новый QR не создаётся;
- `MAIN_31_SBP_SESSION_RECOVERY_TEST.bat` проверяет: create QR → force-stop → restart → recover same session → no second QR.

Живой SmartSkyPOS qrPayment всё ещё не вызывается.