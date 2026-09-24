# CHANGELOG v0.5.113 — SBP callback contract

Дата: 24.09.2026.

Подготовлен production callback-контракт SmartSkyPOS СБП без включения финансового вызова.

Добавлено:
- Kozen bridge version 0.5.4;
- `SbpQrCapture` хранит qrId/payload только в памяти процесса;
- безопасная сводка содержит только SHA-256 short hash и payload length;
- `SbpTransactionCallback` реализует Binder callback slots 1..5;
- slot 2 (`onQrReading`) сохраняет raw QR в памяти и логирует только отпечатки;
- старый `PaymentCallback` также перестал логировать raw qrId;
- INFO / SBP_ROUTE / blocked SBP_RESULT объявляют `CAPTURE_HASHED_V1`;
- JL22 принимает bridge 0.5.2 / 0.5.3 / 0.5.4.

По-прежнему:
- `LIVE_QR_PAYMENT_ENABLED=false`;
- `SbpProductionContract.LIVE_CALL_ENABLED=false`;
- `binder.transact(TX_QR_PAYMENT, ...)` отсутствует;
- реальная СБП-транзакция невозможна.